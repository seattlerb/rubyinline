#!/usr/local/bin/ruby17 -w

# breakeven for build run vs native is about 5000 for 5 factorial
max = 1000000

require "inline"

class MyTest

  include Inline

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

  def factorial_old(*args)
    inline args, "
    int i, f=1;
    for (i = FIX2INT(argv[0]); i >= 1; i--) { f = f * i; }
    return INT2FIX(f);
"
  end
end

t = MyTest.new()

arg = ARGV.pop || 0
arg = arg.to_i

puts "RubyInline #{Inline::VERSION}" if $DEBUG

MyTest.send(:alias_method, :factorial_alias, :factorial_old)

def validate(n)
  if n != 120 then puts "ACK! - #{n}"; end
end

tstart = Time.now
# FIX: this is bogus so I can swap around groups
case arg
when 0 then
  type = "Inline C "
  (1..max).each { |m| n = t.factorial_c(5);     validate(n); }
when 1 then
  type = "Alias    "
  (1..max).each { |m| n = t.factorial_alias(5); validate(n); }
when 2 then
  type = "InlineOld"
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
