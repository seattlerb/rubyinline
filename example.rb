#!/usr/local/bin/ruby -w

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

max = 1000000

puts "RubyInline #{Inline::VERSION}"

if ARGV.length == 0 then
  type = "Inline"
  tstart = Time.now
  (1..max).each { |n| r = t.fastfact(5); if r != 120 then puts "ACK! - #{r}"; end }
  tend = Time.now
else
  type = "Native"
  tstart = Time.now
  (1..max).each { |n| r = t.factorial(5); if r != 120 then puts "ACK! - #{r}"; end }
  tend = Time.now
end

total = tend - tstart
avg = total / max
printf "Type = #{type}, Iter = #{max}, time = %.8f sec, %.8f sec / iter\n", total, avg
