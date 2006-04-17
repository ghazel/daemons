
module Daemons

  require 'daemons/daemonize'
   
  class Monitor
    
    def self.find(dir, app_name)
      pid_file = PidFile.find_files(dir, app_name)[0]
      
      if pid_file
        pid_file = PidFile.existing(pid_file)
        
        unless PidFile.running?(pid_file.read)
          pid_file.remove rescue nil
          return
        end
        
        monitor = self.allocate
      
        monitor.instance_variable_set(:@pid_file, pid_file)
        
        return monitor
      end
      
      return nil
    end
    
    
    def initialize(an_app)
      @pid_file = PidFile.new(an_app.pidfile_dir, an_app.group.app_name + '_monitor', false)
    end
    
    def start(applications)
      return if applications.empty?
      
      fork do
        Daemonize.daemonize
        
        begin  
          @pid_file.write
          
  #         at_exit {
  #           @pid_file.remove rescue nil
  #         }
          
          # This part is needed to remove the pid-file if the application is killed by 
          # daemons or manually by the user.
          # Note that the applications is not supposed to overwrite the signal handler for
          # 'TERM'.
          #
  #         trap('TERM') {
  #           @pid_file.remove rescue nil
  #           exit
  #         }
          
          sleep(60)
          
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
        rescue ::Exception => e
          begin
            File.open(File.join(@pid_file.dir, @pid_file.progname + '.log'), 'a') {|f|
              f.puts Time.now
              f.puts e
              f.puts e.backtrace.inspect
            }
          ensure 
            @pid_file.remove rescue nil
            exit!
          end
        end
      end
      
    end
    
    
    def stop
      Process.kill('TERM', @pid_file.read) rescue nil
      
      # We try to remove the pid-files by ourselves, in case the application
      # didn't clean it up.
      @pid_file.remove rescue nil
    end
    
  end
  
end