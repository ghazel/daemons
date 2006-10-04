lib_dir = File.expand_path(File.join(File.dirname(__FILE__), '../../lib'))

if File.exists?(File.join(lib_dir, 'daemons.rb'))
  $LOAD_PATH.unshift lib_dir
else
  require 'rubygems' rescue nil
end

require 'daemons'

           
Daemons.run_proc('ctrl_proc_simple.rb') do
  loop do
    puts 'ping from proc!'
    sleep(3)
  end
end
