#!/usr/local/bin/ruby -w

$TESTING = true

require 'test/unit'
require 'inline.rb'

# only test classes
class TestInline < Test::Unit::TestCase

  def test_parse_signature
    src = "// stupid cpp comment
    #include \"header.h\"
    /* stupid c comment */
    int
    add(int x, int y) {
      int result = x+y;
      return result;
    }
    "

    expected = {
      'name' => 'add',
      'return' => 'int',
      'args' => [
	[ 'x', 'int' ],
	['y', 'int']
      ]
    }

    result = self.class.parse_signature(src)
    assert_equal(expected, result)
  end

  def test_parse_signature_custom

    self.class.add_inline_type_converter "fooby", "r2c_fooby", "c2r_fooby"

    src = "// stupid cpp comment
    #include \"header.h\"
    /* stupid c comment */
    int
    add(fooby x, int y) {
      int result = x+y;
      return result;
    }
    "

    expected = {
      'name' => 'add',
      'return' => 'int',
      'args' => [
	[ 'x', 'fooby' ],
	['y', 'int']
      ]
    }

    result = self.class.parse_signature(src)
    assert_equal(expected, result)
  end

  def test_parse_signature_register

    self.class.add_inline_type_converter "register int", 'FIX2INT', 'INT2FIX'

    src = "// stupid cpp comment
    #include \"header.h\"
    /* stupid c comment */
    int
    add(register int x, int y) {
      int result = x+y;
      return result;
    }
    "

    expected = {
      'name' => 'add',
      'return' => 'int',
      'args' => [
	[ 'x', 'register int' ],
	['y', 'int']
      ]
    }

    result = self.class.parse_signature(src)
    assert_equal(expected, result)
  end

  ############################################################
  # inline_c_gen tests:

  def util_inline_c_gen(src, expected, expand_types=true)
    result = self.class.inline_c_gen(src, expand_types)
    assert_equal(expected, result)
  end

  def util_inline_c_gen_raw(src, expected)
    util_inline_c_gen(src, expected, false)
  end

  # Ruby Arity Rules, from the mouth of Matz:
  # -2 = ruby array argv
  # -1 = c array argv
  #  0 = self
  #  1 = self, value
  #  2 = self, value, value
  # ...
  # 16 = self, value * 15

  def test_inline_c_gen_raw_arity_0
    src = "VALUE y(VALUE self) {blah;}"

    expected = "static VALUE y(VALUE self) {blah;}"

    util_inline_c_gen_raw(src, expected)
  end

  def test_inline_c_gen_arity_0
    src = "int y() { do_something; return 42; }"

    expected = "static VALUE y(VALUE self) {\n do_something; return INT2FIX(42); }"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_arity_0_no_return
    src = "void y() { do_something; }"

    expected = "static VALUE y(VALUE self) {\n do_something;\nreturn Qnil;\n}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_arity_0_void_return
    src = "void y(void) {go_do_something_external;}"

    expected = "static VALUE y(VALUE self) {
go_do_something_external;\nreturn Qnil;\n}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_arity_0_int_return
    src = "int x() {return 42}"

    expected = "static VALUE x(VALUE self) {
return INT2FIX(42)}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_raw_arity_1
    src = "VALUE y(VALUE self, VALUE obj) {blah;}"

    expected = "static VALUE y(VALUE self, VALUE obj) {blah;}"

    util_inline_c_gen_raw(src, expected)
  end

  def test_inline_c_gen_arity_1
    src = "int y(int x) {blah; return x+1;}"

    expected = "static VALUE y(VALUE self, VALUE _x) {\n  int x = FIX2INT(_x);\nblah; return INT2FIX(x+1);}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_arity_1_no_return
    src = "void y(int x) {blah;}"

    expected = "static VALUE y(VALUE self, VALUE _x) {\n  int x = FIX2INT(_x);\nblah;\nreturn Qnil;\n}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_raw_arity_2
    src = "VALUE func(VALUE self, VALUE obj1, VALUE obj2) {blah;}"

    expected = "static VALUE func(VALUE self, VALUE obj1, VALUE obj2) {blah;}"

    util_inline_c_gen_raw(src, expected)
  end

  def test_inline_c_gen_arity_2
    src = "int func(int x, int y) {blah; return x+y;}"

    expected = "static VALUE func(VALUE self, VALUE _x, VALUE _y) {\n  int x = FIX2INT(_x);\n  int y = FIX2INT(_y);\nblah; return INT2FIX(x+y);}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_raw_arity_3
    src = "VALUE func(VALUE self, VALUE obj1, VALUE obj2, VALUE obj3) {blah;}"

    expected = "static VALUE func(VALUE self, VALUE obj1, VALUE obj2, VALUE obj3) {blah;}"

    util_inline_c_gen_raw(src, expected)
  end

  def test_inline_c_gen_arity_3
    src = "int func(int x, int y, int z) {blah; return x+y+z;}"

    expected = "static VALUE func(int argc, VALUE *argv, VALUE self) {\n  int x = FIX2INT(argv[0]);\n  int y = FIX2INT(argv[1]);\n  int z = FIX2INT(argv[2]);\nblah; return INT2FIX(x+y+z);}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_comments
    src = "// stupid cpp comment
    /* stupid c comment */
    int
    add(int x, int y) { // add two numbers
      return x+y;
    }
    "

    expected = "static VALUE add(VALUE self, VALUE _x, VALUE _y) {
  int x = FIX2INT(_x);
  int y = FIX2INT(_y);
       return INT2FIX(x+y);
    }
    "

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_local_header
    src = "// stupid cpp comment
#include \"header\"
/* stupid c comment */
int
add(int x, int y) { // add two numbers
  return x+y;
}
"
    # FIX: should be 2 spaces before the return. Can't find problem.
    expected = "#include \"header\"
static VALUE add(VALUE self, VALUE _x, VALUE _y) {
  int x = FIX2INT(_x);
  int y = FIX2INT(_y);
   return INT2FIX(x+y);
}
"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_system_header
    src = "// stupid cpp comment
#include <header>
/* stupid c comment */
int
add(int x, int y) { // add two numbers
  return x+y;
}
"

    expected = "#include <header>
static VALUE add(VALUE self, VALUE _x, VALUE _y) {
  int x = FIX2INT(_x);
  int y = FIX2INT(_y);
   return INT2FIX(x+y);
}
"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_wonky_return
    src = "unsigned\nlong z(void) {return 42}"

    expected = "static VALUE z(VALUE self) {
return UINT2NUM(42)}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_gen_compact
    src = "int add(int x, int y) {return x+y}"

    expected = "static VALUE add(VALUE self, VALUE _x, VALUE _y) {
  int x = FIX2INT(_x);
  int y = FIX2INT(_y);
return INT2FIX(x+y)}"

    util_inline_c_gen(src, expected)
  end

  def test_inline_c_char_star_normalize
    src = "char\n\*\n  blah(  char*s) {puts(s); return s}"

    expected = "static VALUE blah(VALUE self, VALUE _s) {
  char * s = STR2CSTR(_s);
puts(s); return rb_str_new2(s)}"

    util_inline_c_gen(src, expected)
  end

end

