# -*- ruby -*- 

require 'rake'
require 'rake/contrib/sshpublisher'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'
require 'rbconfig'

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

desc 'Generate RDoc'
Rake::RDocTask.new :rdoc do |rd|
  rd.rdoc_dir = 'doc'
  rd.rdoc_files.add 'inline.rb', 'inline_package', 'README.txt', 'History.txt'
  rd.main = 'README.txt'
  rd.options << '-t RubyInline RDoc'
end

desc 'Upload RDoc to RubyForge'
task :upload => :rdoc do
  config = YAML.load(File.read(File.expand_path("~/.rubyforge/config.yml")))
  user = "#{config["username"]}@rubyforge.org"
  project = '/var/www/gforge-projects/rubyinline'
  local_dir = 'doc'
  pub = Rake::SshDirPublisher.new user, project, local_dir
  pub.upload
end

require 'rubygems'
require './inline.rb'

spec = Gem::Specification.new do |s|

  s.name = 'RubyInline'
  s.version = Inline::VERSION
  s.summary = "Multi-language extension coding within ruby."

  paragraphs = File.read("README.txt").split(/\n\n+/)
  s.description = paragraphs[3]
  puts s.description

  s.requirements << "A POSIX environment and a compiler for your language."
  s.files = IO.readlines("Manifest.txt").map {|f| f.chomp }

  s.bindir = "."
  s.executables = ['inline_package']
  puts "Executables = #{s.executables.join(", ")}"

  s.require_path = '.' 
  s.autorequire = 'inline'

  s.has_rdoc = false                            # I SUCK - TODO
  s.test_suite_file = "test_inline.rb"

  s.author = "Ryan Davis"
  s.email = "ryand-ruby@zenspider.com"
  s.homepage = "http://www.zenspider.com/ZSS/Products/RubyInline/"
  s.rubyforge_project = "rubyinline"
end

if $0 == __FILE__
  Gem.manage_gems
  Gem::Builder.new(spec).build
end

desc 'Build Gem'
Rake::GemPackageTask.new spec do |pkg|
  pkg.need_tar = true
end

task :install do
  install 'inline.rb', RUBYLIB, :mode => 0444
  install 'inline_package', File.join(PREFIX, 'bin'), :mode => 0555
end

task :uninstall do
  rm File.join(RUBYLIB, 'inline.rb')
  rm File.join(PREFIX, 'bin', 'inline_package')
end

task :clean => [ :clobber_rdoc, :clobber_package ] do
  rm Dir["*~"]
  rm_rf %w(~/.ruby_inline) 
end
