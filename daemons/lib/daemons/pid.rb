
module Daemons

  class Pid
  
    def Pid.running?(pid, additional = nil)
      match_pid = Regexp.new("^\\s*#{pid}\\s")
      got_match = false

      ps_all = IO.popen("ps ax") # the correct syntax is without a dash (-)
      ps_all.each { |psline|
        next unless psline =~ match_pid
        got_match = true
        got_match = false if additional and psline !~ /#{additional}/
        break
      }
      ps_all.close

      return got_match
    end
    
    
    # Returns the directory that should be used to write the pid file to
    # depending on the given mode.
    # 
    # Some modes may require an additionaly hint, others may determine 
    # the directory automatically.
    #
    # If no valid directory is found, returns nil.
    #
    def Pid.dir(dir_mode, dir, script)
      # nil script parameter is allowed so long as dir_mode is not :script
      return nil if dir_mode == :script && script.nil?                         
      
      case dir_mode
        when :normal
          return File.expand_path(dir)
        when :script
          return File.expand_path(File.join(File.split(script)[0],dir))
        when :system  
          return '/var/run'
        else
          raise Error.new("pid file mode '#{dir_mode}' not implemented")
      end
    end
    
    # Initialization method
    def initialize
    end
    
    
    # Get method
    def pid
    end
    
    # Set method
    def pid=(p)
    end
    
    # Cleanup method
    def cleanup
    end
    
    # Exists? method
    def exists?
      true
    end
    
  end  
  
  
end