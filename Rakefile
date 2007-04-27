# -*- ruby -*- 

require 'rubygems'
require 'hoe'

require './lib/inline.rb'

Hoe.new("RubyInline", Inline::VERSION) do |p|
  p.summary = "Multi-language extension coding within ruby."
  p.description = p.paragraphs_of("README.txt", 3).join
  p.url = p.paragraphs_of("README.txt", 1).join
  p.changes = p.paragraphs_of("History.txt", 0..1).join
  p.clean_globs << File.expand_path("~/.ruby_inline")

  p.spec_extras[:requirements] = "A POSIX environment and a compiler for your language."
end

task :examples do
  %w(example.rb example2.rb tutorial/example1.rb tutorial/example2.rb).each do |e|
    rm_rf '~/.ruby_inline'
    ruby "-Ilib -w #{e}"
  end
end

task :bench do
  verbose(false) do
    ruby "-Ilib ./example.rb"
    ruby "-Ilib ./example.rb 1000000 12" # 12 is the bignum cutoff for factorial
  end
end
