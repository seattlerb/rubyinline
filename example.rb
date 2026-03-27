#!/usr/local/bin/ruby -w

require 'rubygems'
$:.unshift 'lib'
require 'inline'

require 'fileutils'
FileUtils.rm_rf File.expand_path("~/.ruby_inline")

class MyTest

  def factorial(n)
    f = 1
    n.downto(2) { |x| f *= x }
    f
  end

  inline do |builder|
    builder.c <<~EOC
      unsigned long factorial_c(int max) {
        int i=max, result=1;
        while (i >= 2) { result *= i--; }
        return result;
      }
    EOC

    builder.c_raw <<~EOC
      static
      VALUE
      factorial_c_raw(int argc, VALUE *argv, VALUE self) {
        int i=FIX2INT(argv[0]), result=1;
        while (i >= 2) { result *= i--; }
        return INT2NUM(result);
      }
    EOC

    # header isn't published but the function isn't static?
    builder.prefix "VALUE rb_int_mul(VALUE x, VALUE y);"

    builder.add_id "*"

    builder.c <<~EOC
      VALUE factorial_c_rb(int max) {
        int i=max;
        VALUE result = INT2NUM(1);
        while (i >= 2) { result = rb_funcall(result, id_times, 1, INT2FIX(i--)); }

        return result;
      }
    EOC
  end

  alias factorial_alias factorial_c_raw
end

# breakeven for build run vs native doing 5 factorial:
#   on a PIII/750 running FreeBSD:        about 5000
#   on a PPC/G4/800 running Mac OSX 10.2: always faster

require 'benchmark/ips'
puts "RubyInline #{Inline::VERSION}" if $DEBUG

t = MyTest.new
n   = (ARGV.shift || 5).to_i
m   = t.factorial n

warn "warning: N > 12 is prolly gonna fail on the C side" if n > 12

def validate n, m
  raise "#{n} != #{m}" unless n == m
end
validate t.factorial_c_raw(n), m if n <= 12
validate t.factorial_c_rb(n),  m
validate t.factorial_alias(n), m if n <= 12
validate t.factorial_c(n),     m if n <= 12
validate t.factorial(n),       m

puts "factorial(n = #{n}) = #{m}"
Benchmark.ips do |x|
  x.config warmup: 1

  x.report "null_time"  do |max|
    max.times do
      # do nothing
    end
  end

  x.report "c"  do |max|
    max.times do
      t.factorial_c n
    end
  end if n <= 12

  x.report "c-raw"  do |max|
    max.times do
      t.factorial_c_raw n
    end
  end if n <= 12

  x.report "c-alias"  do |max|
    max.times do
      t.factorial_alias n
    end
  end if n <= 12

  x.report "c-rb"  do |max|
    max.times do
      t.factorial_c_rb n
    end
  end

  x.report "pure ruby"  do |max|
    max.times do
      t.factorial n
    end
  end

  x.compare!
end
