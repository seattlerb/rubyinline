#!/usr/local/bin/ruby17 -w

$INLINE_FLAGS = " -x c++ "
$INLINE_LIBS  = " -lstdc++ "

require "inline"

class MyTest

  inline_c "
// stupid c++ comment
#include <iostream>
/* stupid c comment */
static
VALUE
hello(int i) {
  while (i-- > 0) {
    std::cout << \"hello\" << std::endl;
  }
}
"
end

t = MyTest.new()

t.hello(3)
