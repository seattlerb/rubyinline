require 'rbconfig'
require 'rake/rdoctask'

PREFIX = ENV['PREFIX'] || Config::CONFIG['prefix']
RUBYLIB = Config::CONFIG['sitelibdir']

task :default => :test

task :test do
  ruby %(-I. -w ./test_inline.rb)
end

task :examples do
  %w(example.rb example2.rb tutorial/example1.rb tutorial/example2.rb).each do |e|
    rm_rf '~/.ruby_inline'
    ruby "-I. -w #{e}"
  end
end

Rake::RDocTask.new(:docs) do |rd|
  rd.main = "inline.rb"
end

task :bench do
  verbose(false) do
    puts "Running native"
    ruby "-I. ./example.rb 3"
    puts "Running primer - preloads the compiler and stuff"
    rm_rf '~/.ruby_inline'
    ruby "-I. ./example.rb 0"
    puts "With full builds"
    (0..2).each do |i|
      rm_rf '~/.ruby_inline'
      ruby "-I. ./example.rb #{i}"
    end
    puts "Without builds"
    (0..2).each do |i|
      ruby "-I. ./example.rb #{i}"
    end
  end
end

task :install do
  install 'inline.rb', RUBYLIB, :mode => 0444
  install 'inline_package', File.join(PREFIX, 'bin'), :mode => 0555
end

task :uninstall do
  rm_f File.join(RUBYLIB, 'inline.rb')
  rm_f File.join(PREFIX, 'bin', 'inline_package')
end

task :clean do
  rm_rf %w(*~ doc ~/.ruby_inline)
end
