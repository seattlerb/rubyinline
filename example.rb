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

  def fastfact(*args)
    inline args, <<-END
    int i, f=1;
    for (i = FIX2INT(argv[0]); i >= 1; i--) { f = f * i; }
    return INT2FIX(f);
    END
  end

end

t = MyTest.new()

arg = ARGV.pop || 0
arg = arg.to_i

puts "RubyInline #{Inline::VERSION}" if $DEBUG

MyTest.send(:alias_method, :testmethod, :fastfact)

def validate(n)
  if n != 120 then puts "ACK! - #{n}"; end
end

tstart = Time.now
if arg == 0 then
  type = "Alias "
  (1..max).each { |m| n = t.testmethod(5); validate(n); }
elsif arg == 1 then
  type = "Inline"
  (1..max).each { |m| n = t.fastfact(5);   validate(n); }
elsif arg == 2 then
  type = "Native"
  (1..max).each { |m| n = t.factorial(5);  validate(n); }
else
  $stderr.puts "ERROR: argument #{arg} not recognized"
  exit(1)
end
tend = Time.now

total = tend - tstart
avg = total / max
printf "Type = #{type}, Iter = #{max}, time = %.8f sec, %.8f sec / iter\n", total, avg
