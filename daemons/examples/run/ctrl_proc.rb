lib_dir = File.expand_path(File.join(File.split(__FILE__)[0], '../../lib'))

if File.exists?(File.join(lib_dir, 'daemons.rb'))
  $LOAD_PATH.unshift lib_dir
else
  require 'rubygems' rescue nil
end

require 'daemons'


options = {
             :multiple   => false,
             :ontop      => false,
             :backtrace  => true,
             :log_output => true,
             :monitor    => true
           }
           
Daemons.run_proc('ctrl_proc.rb', options) do
  loop do
    puts 'ping from proc!'
    sleep(3)
  end
end