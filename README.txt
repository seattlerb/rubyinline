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
+ Rudimentary automatic conversion between ruby and C basic types
  (char, unsigned, unsigned int, char *, int, long, unsigned long).
+ Only recompiles if the C code has changed.
+ Pretends to be secure.
+ Only uses standard ruby libraries, nothing extra to download.
+ Simple as it can be. Less than 350 lines long... um... sorta simple.
- Currently doesn't munge ruby names that aren't compatible in C (ex: a!())

SYNOPSYS:

  require "inline"
  class MyTest
    inline_c "
      long factorial(int max) {
        int i=max, result=1;
        while (i >= 2) { result *= i--; }
        return result;
      }"
  end
  t = MyTest.new()
  factorial_5 = t.factorial(5)

Produces:

  % rm ~/.ruby_inline/*
  % ./example.rb 0
  Type = Inline C , Iter = 1000000, T = 7.12203800 sec, 0.00000712 sec / iter
  % ./example.rb 0
  Type = Inline C , Iter = 1000000, T = 7.11633600 sec, 0.00000712 sec / iter
  % ./example.rb 1
  WARNING: Inline#inline is deprecated, use Module#inline_c
  Type = Alias    , Iter = 1000000, T = 7.27398900 sec, 0.00000727 sec / iter
  % ./example.rb 2
  WARNING: Inline#inline is deprecated, use Module#inline_c
  Type = InlineOld, Iter = 1000000, T = 7.10194600 sec, 0.00000710 sec / iter
  % ./example.rb 3
  Type = Native   , Iter = 1000000, T = 22.10488600 sec, 0.00002210 sec / iter

REQUIREMENTS:

+ Ruby - 1.6.7 & 1.7.2 has been used on FreeBSD 4.6.
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
