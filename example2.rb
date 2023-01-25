#!/usr/local/bin/ruby17 -w

begin
  require 'rubygems'
rescue LoadError
  $: << 'lib'
end
require 'inline'

class MyTest

  inline do |builder|
    builder.include_ruby_last

    builder.add_compile_flags %q(-x c++)
    builder.add_link_flags %q(-lstdc++)

    builder.include "<iostream>"
    builder.include '"ruby/version.h"'

    builder.c "
static
void
hello(int i) {
  while (i-- > 0) {
    std::cout << \"hello\" << std::endl;
  }
}
"
  end
end

t = MyTest.new()

t.hello(3)
