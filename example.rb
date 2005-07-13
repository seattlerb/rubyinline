#!/usr/local/bin/ruby -w

begin require 'rubygems' rescue LoadError end
require 'inline'

class MyTest

  def factorial(n)
    f = 1
    n.downto(2) { |x| f *= x }
    f
  end

  inline do |builder|
    builder.include "<math.h>"

    builder.c "
    long factorial_c(int max) {
      int i=max, result=1;
      while (i >= 2) { result *= i--; }
      return result;
    }"

    builder.c_raw "
    static
    VALUE
    factorial_c_raw(int argc, VALUE *argv, VALUE self) {
      int i=FIX2INT(argv[0]), result=1;
      while (i >= 2) { result *= i--; }
      return INT2NUM(result);
    }"
  end
end

t = MyTest.new()

arg = ARGV.shift || 0
arg = arg.to_i

# breakeven for build run vs native doing 5 factorial:
#   on a PIII/750 running FreeBSD:        about 5000
#   on a PPC/G4/800 running Mac OSX 10.2: always faster
max = ARGV.shift || 1000000
max = max.to_i

puts "RubyInline #{Inline::VERSION}" if $DEBUG

MyTest.send(:alias_method, :factorial_alias, :factorial_c_raw)

def validate(n)
  if n != 120 then puts "ACK! - #{n}"; end
end

tstart = Time.now
case arg
when 0 then
  type = "Inline C "
  (1..max).each { |m| n = t.factorial_c(5);     validate(n); }
when 1 then
  type = "InlineRaw"
  (1..max).each { |m| n = t.factorial_c_raw(5); validate(n); }
when 2 then
  type = "Alias    "
  (1..max).each { |m| n = t.factorial_alias(5); validate(n); }
when 3 then
  type = "Native   "
  (1..max).each { |m| n = t.factorial(5);       validate(n); }
else
  $stderr.puts "ERROR: argument #{arg} not recognized"
  exit(1)
end
tend = Time.now

total = tend - tstart
avg = total / max
printf "Type = #{type}, Iter = #{max}, T = %.8f sec, %.8f sec / iter\n", total, avg
