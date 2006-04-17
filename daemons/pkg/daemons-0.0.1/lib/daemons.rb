require 'optparse'
require 'optparse/time'

require 'daemons/pidfile'  
require 'daemons/cmdline'
require 'daemons/exceptions'


# All functions and classes that Daemons provides reside in this module.
#
# The function you should me most interested in is Daemons#run, because it is
# the only function you need to invoke directly from your scripts.
#
# Also, you are maybe interested in reading the documentation for the class PidFile.
# There you can find out about how Daemons works internally and how and where the so
# called <i>Pid-Files</i> are stored.
#
module Daemons

  VERSION = "0.2.0"
  
  require 'daemons/daemonize'
   
  
  class Application
  
    attr_accessor :app_argv
    attr_accessor :controller_argv
    
    # the PidFile instance belonging to this application
    attr_reader :pid_file
    
    # the ApplicationGroup the application belongs to
    attr_reader :group
    
    
    def initialize(group, pid_file = nil)
      @group = group
      
      @pid_file = (pid_file || PidFile.new(pidfile_dir(), @group.app_name, @group.multiple))
    end
    
    def script
      @script || @group.script
    end
    
    def pidfile_dir
      PidFile.dir(@dir_mode || @group.dir_mode, @dir || @group.dir, @script || @group.script)
    end
    
    def start
      opts = @group.controller.options
      
      unless opts[:ontop]
        Daemonize.daemonize()
      end
      
      @pid_file.write
      
      if opts[:exec]
        run_via_exec()
      else
        # We need this to remove the pid-file if the applications exits by itself.
        # Note that <tt>at_text</tt> will only be run if the applications exits by calling 
        # <tt>exit</tt>, and not if it calls <tt>exit!</tt>.
        #
        at_exit {
          @pid_file.remove rescue nil
          
          # If the option <tt>:backtrace</tt> is used and the application did exit by itself
          # create a exception log.
          if opts[:backtrace] and not opts[:ontop] and not $daemons_sigterm
            exception_log() rescue nil
          end
            
        }
        
        # This part is needed to remove the pid-file if the application is killed by 
        # daemons or manually by the user.
        # Note that the applications is not supposed to overwrite the signal handler for
        # 'TERM'.
        #
        trap('TERM') {
          @pid_file.remove rescue nil
          $daemons_sigterm = true
          
          exit
        }
        
        run_via_load()
      end
    end
    
    def run
      if @group.controller.options[:exec]
        run_via_exec()
      else
        run_via_load()
      end
    end
     
    def run_via_exec
      ENV['DAEMONS_ARGV'] = @controller_argv.join(' ')      # haven't tested yet if this is really passed to the exec'd process...
      
      Kernel.exec(script(), *ARGV)
    end
    
    def run_via_load
      $DAEMONS_ARGV = @controller_argv
      ENV['DAEMONS_ARGV'] = @controller_argv.join(' ')
      
      ARGV.clear
      ARGV.concat @app_argv if @app_argv
      
      # TODO: begin - rescue - end around this and exception logging
      load script()
    end
    
    # This is a nice little function for debugging purposes:
    # In case a multi-threaded ruby script exits due to an uncaught exception
    # it may be difficult to find out where the exception came from because
    # one cannot catch exceptions that are thrown in threads other than the main
    # thread.
    #
    # This function searches for all exceptions in memory and outputs them to STDERR
    # (if it is connected) and to a log file in the pid-file directory.
    #
    def exception_log
      require 'logger'
      
      l_file = Logger.new(File.join(pidfile_dir(), @group.app_name + '.log'))
      
      
      # the code below only logs the last exception
      e = nil
      
      ObjectSpace.each_object {|o|
        if ::Exception === o
          e = o
        end
      }
      
      l_file.error e
      l_file.close
      
      e = nil
      
      # this code logs every exception found in memory
#       ObjectSpace.each_object {|o|
#         if ::Exception === o
#           l_file.error o
#         end
#       }
#       
#       l_file.close
    end
    
    
    def stop
      Process.kill('TERM', @pid_file.read)
      
      # We try to remove the pid-files by ourselves, in case the application
      # didn't clean it up.
      @pidfile.remove rescue nil
      
    end
    
    def zap
      @pid_file.remove
    end
    
  end
  
  
  class ApplicationGroup
  
    attr_reader :app_name
    attr_reader :script
    
    attr_reader :controller
    
    attr_reader :applications
    
    attr_accessor :controller_argv
    attr_accessor :app_argv
    
    attr_accessor :dir_mode
    attr_accessor :dir
    
    # true if the application is supposed to run in multiple instances
    attr_reader :multiple
    
    
    def initialize(app_name, script, controller) #multiple = false)
      @app_name = app_name
      @script = script
      @controller = controller
      
      options = controller.options
      
      @multiple = options[:multiple] || false
      
      @dir_mode = options[:dir_mode] || :script
      @dir = options[:dir] || ''
      
      @applications = find_applications(pidfile_dir())
    end
    
    def pidfile_dir
      PidFile.dir(@dir_mode, @dir, script)
    end  
    
    def find_applications(dir)
      pid_files = PidFile.find_files(dir, app_name)
      
      #pp pid_files
      
      return pid_files.map {|f| Application.new(self, PidFile.existing(f))}
    end
    
    def new_application(script = nil)
      if @applications.size > 0 and not @multiple
        raise RuntimeException.new('there is already one or more instance(s) of the program running')
      end
      
      app = Application.new(self)
      
      app.controller_argv = @controller_argv
      app.app_argv = @app_argv
      
      @applications << app
      
      return app
    end
    
    def start_all
      @applications.each {|a| fork { a.start } }
    end
    
    def stop_all
      @applications.each {|a| a.stop}
    end
    
    def zap_all
      @applications.each {|a| a.zap}
    end
    
  end

  
  class Controller
    
    attr_reader :app_name
    attr_reader :options
    
    
    COMMANDS = [
      'start',
      'stop',
      'restart',
      'run',
      'zap'
    ]
    
    def initialize(script, argv = [])
      @argv = argv
      @script = File.expand_path(script)
      
      @app_name = File.split(@script)[1]
      
      @command, @controller_part, @app_part = Controller.split_argv(argv)
      
      #@options[:dir_mode] ||= :script
      
      @optparse = Optparse.new(self)
    end
    
    
    # This function is used to do a final update of the options passed to the application
    # before they are really used.
    #
    # Note that this function should only update <tt>@options</tt> and no other variables.
    #
    def setup_options
      #@options[:ontop] ||= true
    end
    
    def run(options = {})
      @options = options
      
      @options.update @optparse.parse(@controller_part).delete_if {|k,v| !v}
      
      setup_options()
      
      #pp @options

      @group = ApplicationGroup.new(@app_name, @script, self) #options)
      @group.controller_argv = @controller_part
      @group.app_argv = @app_part
      
      case @command
        when 'start'
          @group.new_application.start
        when 'run'
          @group.new_application.run
        when 'stop'
          @group.stop_all
        when 'restart'
          @group.stop_all
          sleep 1
          @group.start_all
        when 'zap'
          @group.zap_all
        when nil
          raise CmdException.new('no command given')
          #puts "ERROR: No command given"; puts
          
          #print_usage()
          #raise('usage function not implemented')
        else
          raise Error.new("command '#{@command}' not implemented")
      end
    end
    
    
    # Split an _argv_ array.
    # +argv+ is assumed to be in the following format:
    #   ['command', 'controller option 1', 'controller option 2', ..., '--', 'app option 1', ...]
    #
    # <tt>command</tt> must be one of the commands listed in <tt>COMMANDS</tt>
    #
    # *Returns*: the command as a string, the controller options as an array, the appliation options
    # as an array
    #
    def Controller.split_argv(argv)
      argv = argv.dup
      
      command = nil
      controller_part = []
      app_part = []
       
      if COMMANDS.include? argv[0]
        command = argv.shift
      end
      
      if i = argv.index('--')
        controller_part = argv[0..i-1]
        app_part = argv[i+1..-1]
      else
        controller_part = argv[0..-1]
      end
       
      return command, controller_part, app_part
    end
  end
  
  
  # Passes control to Daemons.
  #
  # +script+::  This is the path to the script that should be run as a daemon.
  #             Please note that Daemons runs this script with <tt>load <script></tt>.
  #             Also note that Daemons cannot detect the directory in which the controlling
  #             script resides, so this has to be either an absolute path or you have to run
  #             the controlling script from the appropriate directory.
  #
  # +options+:: A hash that may contain one or more of options listed below
  #
  # === Options:
  # <tt>:dir_mode</tt>::  Either <tt>:script</tt> (the directory for writing the pid files to 
  #                       given by <tt>:dir</tt> is interpreted relative
  #                       to the script location given by +script+) or <tt>:normal</tt> (the directory given by 
  #                       <tt>:dir</tt> is interpreted relative to the current directory) or <tt>:system</tt> 
  #                       (<tt>/var/run</tt> is used as the pid file directory)
  #
  # <tt>:dir</tt>::       Used in combination with <tt>:dir_mode</tt> (description above)
  # <tt>:multiple</tt>::  Specifies whether multiple instances of the same script are allowed to run at the
  #                       same time
  #
  # -----
  # 
  # === Example:
  #   options = {
  #     :dir_mode   => :script,
  #     :dir        => 'pids',
  #     :multiple   => true
  #   }
  #
  #   Daemons.run(File.join(File.split(__FILE__)[0], 'myscript.rb'), options)
  #
  def run(script, options = {})
    @controller = Controller.new(script, ARGV)
    
    #pp @controller
    
    @controller.catch_exceptions {
      @controller.run(options)
    }
  end
  module_function :run
  
end 
