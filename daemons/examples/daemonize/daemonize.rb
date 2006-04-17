lib_dir = File.expand_path(File.join(File.split(__FILE__)[0], '../../lib'))

if File.exists?(File.join(lib_dir, 'daemons.rb'))
  $LOAD_PATH.unshift lib_dir
else
  require 'rubygems' rescue nil
end



require 'daemons'


testfile = File.expand_path(__FILE__) + '.log'

Daemons.daemonize

File.open(testfile, 'w') {|f|
  f.write("test")
}