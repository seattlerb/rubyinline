#!/usr/local/bin/ruby -w

require "inline"

class MyTest

  include Inline

  def myfastmethod(*args)
    inline args, <<-END
    return INT2FIX(FIX2INT(argv[0]) + FIX2INT(argv[1]));
    END
  end

  def myslowmethod(a, b)
    return a+b
  end

end

t = MyTest.new()

max = 100000

if ARGV.length == 0 then
  puts "Inline::C"
  (1..max).each { |n| r = t.myfastmethod(1, 2); if r != 3 then puts "ACK!"; end }
else
  puts "Native"
  (1..max).each { |n| r = t.myslowmethod(1, 2); if r != 3 then puts "ACK!"; end }
end
