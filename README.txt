Ruby Inline
    http://www.zenspider.com/Languages/Ruby/
    support@zenspider.com

DESCRIPTION:
  
Ruby Inline is my quick attempt to create an analog to Perl's
Inline::C. It allows you to embed C external module code in your ruby
script directly. The code is compiled and run on the fly when
needed. The ruby version isn't near as feature-full as the perl
version, but it is neat!

FEATURES/PROBLEMS:
  
+ Quick and easy inlining of your C code embedded in your ruby script.
+ Only recompiles if the C code has changed.
+ Pretends to be secure.
+ Only uses standard ruby libraries, nothing extra to download.
+ Simple as it can be. Less than 125 lines long.
- Currently doesn't munge ruby names that aren't compatible in C (ex: a!())

SYNOPSYS:

  require "inline"
  class MyTest
    include Inline
    def fastfact(*args)
      inline args, <<-END
      int i, f=1;
      for (i = FIX2INT(argv[0]); i >= 1; i--) { f = f * i; }
      return INT2FIX(f);
      END
    end
  end
  t = MyTest.new()
  factorial_5 = t.fastfact(5)

Produces:

  <502> rm /tmp/Mod_MyTest_fastfact.*; ./example.rb 
  RubyInline 1.0.4
  Building /tmp/Mod_MyTest_fastfact.so with 'cc -shared -O -pipe  -fPIC -I /usr/local/lib/ruby/1.6/i386-freebsd4'
  Type = Inline, Iter = 1000000, time = 5.37746200 sec, 0.00000538 sec / iter
  <503> ./example.rb 
  RubyInline 1.0.4
  Type = Inline, Iter = 1000000, time = 5.26147500 sec, 0.00000526 sec / iter
  <504> ./example.rb native
  RubyInline 1.0.4
  Type = Native, Iter = 1000000, time = 24.09801500 sec, 0.00002410 sec / iter

REQUIREMENTS:

+ Ruby - 1.6.7 has been used on FreeBSD 4.6.
+ POSIX compliant system (ie pretty much any UNIX, or Cygwin on MS platforms).
+ A C compiler (the same one that compiled your ruby interpreter).

INSTALL:

+ no install instructions yet.

LICENSE:

(The MIT License)

Copyright (c) 2001-2002 Ryan Davis, Zen Spider Software

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
