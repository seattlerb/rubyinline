#!/usr/local/bin/ruby17 -w

$INLINE_FLAGS = " -x c++ "
$INLINE_LIBS  = " -lstdc++ "

require "inline"

class MyTest

  inline_c_raw "
// stupid c++ comment
#include <iostream>
/* stupid c comment */
static
VALUE
hello(int argc, VALUE *argv, VALUE self) {
  std::cout << \"hello\" << std::endl;
}
"
end

t = MyTest.new()

t.hello
