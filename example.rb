#!/usr/local/bin/ruby17 -w

# breakeven for build run vs native is about 5000 for 5 factorial
max = 1000000

require "inline"

class MyTest

  def factorial(n)
    f = 1
    n.downto(1) { |x| f = f * x }
    f
  end

  inline_c "
    long factorial_c(int max) {
      int i=max, result=1;
      while (i >= 2) { result *= i--; }
      return result;
    }"

  inline_c_raw "
    #include <math.h>
    static
    VALUE
    factorial_c_raw(int argc, VALUE *argv, VALUE self) {
      int i, f=1;
      for (i = FIX2INT(argv[0]); i >= 1; i--) { f = f * i; }
      return INT2NUM(f);
    }"
end

t = MyTest.new()

arg = ARGV.pop || 0
arg = arg.to_i

puts "RubyInline #{INLINE_VERSION}" if $DEBUG

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
