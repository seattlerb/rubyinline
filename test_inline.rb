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

  def util_inline_c(src, expected)
    result = self.class.inline_c_gen(src).gsub(/\s+$/, '').gsub(/^\s+/, '')
    expected = expected.gsub(/\s+$/, '').gsub(/^\s+/, '')

    assert_equal(expected, result)
  end

  def test_inline_c_gen_void_nil
    src = "void y() {go_do_something_external;}"

    expected = "static VALUE y(int argc, VALUE *argv, VALUE self) {
      go_do_something_external;}"

    util_inline_c(src, expected)
  end

  def test_inline_c_gen_void_void
    src = "void y(void) {go_do_something_external;}"

    expected = "static VALUE y(int argc, VALUE *argv, VALUE self) {
      go_do_something_external;}"

    util_inline_c(src, expected)
  end

  def test_inline_c_gen_int_nil
    src = "int x() {return 42}"

    expected = "static VALUE x(int argc, VALUE *argv, VALUE self) {
      return INT2FIX(42)}"

    util_inline_c(src, expected)
  end

  def test_inline_c_gen_int_int
    src = "int factorial(int n) {
      int i, f=1;
      for (i = n; i >= 1; i--) { f = f * i; }
      return f;
    }
    "

    expected = "static VALUE factorial(int argc, VALUE *argv, VALUE self) {
      int n = FIX2INT(argv[0]);
      int i, f=1;
      for (i = n; i >= 1; i--) { f = f * i; }
      return INT2FIX(f);
    }
    "

    util_inline_c(src, expected)
  end

  def test_inline_c_gen_int_int_int
    src = "// stupid cpp comment
    #include \"header.h\"
    /* stupid c comment */
    int
    add(int x, int y) { // add two numbers
      return x+y;
    }
    "

    expected = "
    #include \"header.h\"

    static VALUE add(int argc, VALUE *argv, VALUE self) {
      int x = FIX2INT(argv[0]);
      int y = FIX2INT(argv[1]);
      return INT2FIX(x+y);
    }
    "

    util_inline_c(src, expected)
  end

  def test_inline_c_gen_ulong_void_wonky
    src = "unsigned\nlong z(void) {return 42}"

    expected = "static VALUE z(int argc, VALUE *argv, VALUE self) {
      return UINT2NUM(42)}"

    util_inline_c(src, expected)
  end

  def test_inline_c_gen_compact
    src = "int add(int x, int y) {return x+y}"

    expected = "static VALUE add(int argc, VALUE *argv, VALUE self) {
      int x = FIX2INT(argv[0]);
      int y = FIX2INT(argv[1]);
      return INT2FIX(x+y)}"

    util_inline_c(src, expected)
  end

  def test_inline_c_str_str
    src = "char\n\*\n  blah(  char*s) {puts(s); return s}"

    expected = "static VALUE blah(int argc, VALUE *argv, VALUE self) {
      char * s = STR2CSTR(argv[0]);
      puts(s); return rb_str_new2(s)}"

    util_inline_c(src, expected)
  end
end

