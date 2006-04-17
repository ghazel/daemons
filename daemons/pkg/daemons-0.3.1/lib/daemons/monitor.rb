
module Daemons

  require 'daemons/daemonize'
   
  class Monitor
    
    def self.find(dir, app_name)
      pid = PidFile.find_files(dir, app_name)[0]
      
      if pid
        pid = PidFile.existing(pid)
        
        unless PidFile.running?(pid.pid)
          pid.cleanup rescue nil
          return
        end
        
        monitor = self.allocate
      
        monitor.instance_variable_set(:@pid, pid)
        
        return monitor
      end
      
      return nil
    end
    
    
    def initialize(an_app)
      if an_app.pidfile_dir
        @pid = PidFile.new(an_app.pidfile_dir, an_app.group.app_name + '_monitor', false)
      else
        @pid = PidMem.new
      end
    end
    
    def watch(applications)
      sleep(30)
      
      loop do
        applications.each {|a|
          sleep(10)
          
          unless a.running?
            a.zap!
            
            Process.detach(fork { a.start })
            
            sleep(10)
          end
        }
        
        sleep(30)
      end
    end
    private :watch
    
    
    def start_with_pidfile(applications)
      fork do
        Daemonize.daemonize
        
        begin  
          @pid.pid = Process.pid
          
  #         at_exit {
  #           @pid.cleanup rescue nil
  #         }
          
          # This part is needed to remove the pid-file if the application is killed by 
          # daemons or manually by the user.
          # Note that the applications is not supposed to overwrite the signal handler for
          # 'TERM'.
          #
  #         trap('TERM') {
  #           @pid.cleanup rescue nil
  #           exit
  #         }
          
          watch(applications)
        rescue ::Exception => e
          begin
            File.open(File.join(@pid.dir, @pid.progname + '.log'), 'a') {|f|
              f.puts Time.now
              f.puts e
              f.puts e.backtrace.inspect
            }
          ensure 
            @pid.cleanup rescue nil
            exit!
          end
        end
      end
    end
    private :start_with_pidfile
    
    def start_without_pidfile(applications)
      Thread.new { watch(applications) }
    end
    private :start_without_pidfile
    
    
    
    def start(applications)
      return if applications.empty?
      
      if @pid.kind_of?(PidFile)
        start_with_pidfile(applications)
      else
        start_without_pidfile(applications)
      end
    end
    
    
    def stop
      Process.kill('TERM', @pid.pid) rescue nil
      
      # We try to remove the pid-files by ourselves, in case the application
      # didn't clean it up.
      @pid.cleanup rescue nil
    end
    
  end
  
end