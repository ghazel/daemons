lib_dir = File.expand_path(File.join(File.split(__FILE__)[0], '../../lib'))

if File.exists?(File.join(lib_dir, 'daemons.rb'))
  $LOAD_PATH.unshift lib_dir
else
  require 'rubygems' rescue nil
end

require 'daemons'


options = {
  :log_output => true,
  :backtrace => true
}

Daemons.run(File.join(File.split(__FILE__)[0], 'myserver_crashing.rb'), options)
