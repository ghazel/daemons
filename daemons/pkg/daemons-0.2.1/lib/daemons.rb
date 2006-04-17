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

  VERSION = "0.2.2"
  
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
        Daemonize.daemonize(opts[:log_output] ? File.join(pidfile_dir(), @group.app_name + '.output') : nil)
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
#       e = nil
#       
#       ObjectSpace.each_object {|o|
#         if ::Exception === o
#           e = o
#         end
#       }
#       
#       l_file.error e
#       l_file.close
      
      # this code logs every exception found in memory
      ObjectSpace.each_object {|o|
        if ::Exception === o
          l_file.error o
        end
      }
      
      l_file.close
    end
    
    
    def stop
      if @group.controller.options[:force] and not running?
        self.zap
        return
      end
      
      Process.kill('TERM', @pid_file.read)
      
      # We try to remove the pid-files by ourselves, in case the application
      # didn't clean it up.
      @pid_file.remove rescue nil
      
    end
    
    def zap
      @pid_file.remove
    end
    
    def show_status
      running = self.running?
      
      puts "#{self.group.app_name}: #{running ? '' : 'not '}running#{(running and @pid_file.exists?) ? ' [pid ' + @pid_file.read.to_s + ']' : ''}#{(@pid_file.exists? and not running) ? ' (but pid-file exists: ' + @pid_file.read.to_s + ')' : ''}"
    end
    
    # This function implements a (probably too simle) method to detect
    # whether the program with the pid found in the pid-file is still running.
    # It just searches for the pid in the output of <tt>ps ax</tt>, which
    # is probably not a good idea in some cases.
    # Alternatives would be to use a direct access method the unix process control
    # system.
    #
    def running?
      if @pid_file.exists?
        return /#{@pid_file.read} / =~ `ps ax`
      end
      
      return false
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
      
      #@applications = find_applications(pidfile_dir())
    end
    
    # Setup the application group.
    # Currently this functions calls <tt>find_applications</tt> which finds
    # all running instances of the application and populates the application array.
    #
    def setup
      @applications = find_applications(pidfile_dir())
    end
    
    def pidfile_dir
      PidFile.dir(@dir_mode, @dir, script)
    end  
    
    def find_applications(dir)
      pid_files = PidFile.find_files(dir, app_name)
      
      #pp pid_files
      
      return pid_files.map {|f| 
        app = Application.new(self, PidFile.existing(f))
        setup_app(app)
        app
      }
    end
    
    def new_application(script = nil)
      if @applications.size > 0 and not @multiple
        if @controller.options[:force]
          @applications.delete_if {|a|
            unless a.running?
              a.zap
              true
            end
          }
        end
        
        raise RuntimeException.new('there is already one or more instance(s) of the program running') unless @applications.empty?
      end
      
      app = Application.new(self)
      
      setup_app(app)
      
      @applications << app
      
      return app
    end
    
    def setup_app(app)
      app.controller_argv = @controller_argv
      app.app_argv = @app_argv
    end
    private :setup_app
    
    def start_all
      @applications.each {|a| fork { a.start } }
    end
    
    def stop_all
      @applications.each {|a| a.stop}
    end
    
    def zap_all
      @applications.each {|a| a.zap}
    end
    
    def show_status
      @applications.each {|a| a.show_status}
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
      'zap',
      'status'
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
      
      @group.setup
      
      case @command
        when 'start'
          @group.new_application.start
        when 'run'
          @group.new_application.run
        when 'stop'
          @group.stop_all
        when 'restart'
          unless @group.applications.empty?
            @group.stop_all
            sleep 1
            @group.start_all
          end
        when 'zap'
          @group.zap_all
        when 'status'
          unless @group.applications.empty?
            @group.show_status
          else
            puts "#{@group.app_name}: no instances running"
          end
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
  # <tt>:ontop</tt>::     When given, stay on top, i.e. do not daemonize the application 
  #                       (but the pid-file and other things are written as usual)
  # <tt>:exec</tt>::      When given, do not start the application by <tt>load</tt>-ing the script file,
  #                       but by exec'ing the script file
  # <tt>:backtrace</tt>:: Write a backtrace of the last exceptions to the file '[app_name].log' in the 
  #                       pid-file directory if the application exits due to an uncaught exception
  #
  # -----
  # 
  # === Example:
  #   options = {
  #     :dir_mode   => :script,
  #     :dir        => 'pids',
  #     :multiple   => true,
  #     :ontop      => true,
  #     :exec       => true,
  #     :backtrace  => true
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
