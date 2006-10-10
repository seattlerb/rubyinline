# -*- ruby -*- 

require 'rubygems'
require 'hoe'

require './inline.rb'

Hoe.new("RubyInline", Inline::VERSION) do |p|
  p.summary = "Multi-language extension coding within ruby."
  p.description = p.paragraphs_of("README.txt", 3).join
  p.clean_globs << File.expand_path("~/.ruby_inline")

  p.spec_extras[:requirements] = "A POSIX environment and a compiler for your language."
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
