require "rbconfig"
require "ftools"

def caller_method_name()
  /\`([^\']+)\'/.match(caller(2).first)[1]
end

def assert_dir_secure(path)
  mode = File.stat(path).mode
  unless ((mode % 01000) & 0022) == 0 then # WARN: POSIX systems only...
    $stderr.puts "#{path} is insecure (#{sprintf('%o', mode)}), needs 0700 for perms" 
    exit 1
  end
end
public :caller_method_name, :assert_dir_secure

$RUBY_INLINE_COMPAT = 0

module Inline

  VERSION = '2.0.0'

  def inline(args, prelude, src=nil)

    $stderr.puts "WARNING: Inline#inline is deprecated, use Module#inline_c"

    if src.nil? then
      src = prelude
      prelude = ""
    end

    rootdir = ENV['INLINEDIR'] || ENV['HOME']
    assert_dir_secure(rootdir)

    tmpdir = rootdir + "/.ruby_inline"
    unless File.directory? tmpdir then
      $stderr.puts "NOTE: creating #{tmpdir} for RubyInline" if $DEBUG
      Dir.mkdir(tmpdir, 0700)
    end
    assert_dir_secure(tmpdir)

    myclass   = self.class
    mymethod  = self.caller_method_name
    mod_name  = "Mod_#{myclass}_#{mymethod}"
    extension = Config::CONFIG["DLEXT"]
    so_name   = "#{tmpdir}/#{mod_name}.#{extension}"

    unless File.file? so_name and File.mtime($0) < File.mtime(so_name) then
      # extracted from mkmf.rb
      srcdir  = Config::CONFIG["srcdir"]
      archdir = Config::CONFIG["archdir"]
      if File.exist? archdir + "/ruby.h"
	hdrdir = archdir
      elsif File.exist? srcdir + "/ruby.h"
	hdrdir = srcdir
      else
	$stderr.puts "ERROR: Can't find header files for ruby. Exiting..."
	exit 1
      end

      # Generating code
      src = %Q{
#include "ruby.h"
#{prelude}

  static VALUE t_#{mymethod}(int argc, VALUE *argv, VALUE self) {
    #{src}
  }

  VALUE c#{mod_name};

  void Init_#{mod_name}() {
    c#{mod_name} = rb_define_module("#{mod_name}");
    rb_define_method(c#{mod_name}, "_#{mymethod}", t_#{mymethod}, -1);
  }
}

      src_name = "#{tmpdir}/#{mod_name}.c"

      # move previous version to the side if it exists
      test_cmp = false
      old_src_name = src_name + ".old"
      if test ?f, src_name then
	test_cmp = true
	File.rename src_name, old_src_name
      end

      f = File.new(src_name, "w")
      f.puts src
      f.close

      # recompile only if the files are different
      recompile = true
      if test_cmp and File::compare(old_src_name, src_name, $DEBUG) then
	recompile = false
      end

      if recompile then

	cmd = "#{Config::CONFIG['LDSHARED']} #{Config::CONFIG['CFLAGS']} -I #{hdrdir} -o #{so_name} #{src_name}"
	
	if /mswin32/ =~ RUBY_PLATFORM then
	  cmd += " -link /INCREMENTAL:no /EXPORT:Init_#{mod_name}"
	end
	
	$stderr.puts "Building #{so_name} with '#{cmd}'" if $DEBUG
	`#{cmd}`
      end
    end

    # Loading & Replacing w/ new method
    require "#{so_name}"
    myclass.class_eval("include #{mod_name}")
    myclass.class_eval("alias_method :old_#{mymethod}, :#{mymethod}")

    if RUBY_VERSION >= "1.7.2" then
      oldmeth = myclass.instance_method(mymethod)
      old_method_name = "old_#{mymethod}"
      myclass.instance_methods.each { |methodname|
	if methodname != old_method_name then
	  meth = myclass.instance_method(methodname)
	  if meth == oldmeth then
	    myclass.class_eval("alias_method :#{methodname}, :_#{mymethod}")
	  end
	end
      }
    else
      if $RUBY_INLINE_COMPAT == 0 then
	$stderr.puts "WARNING: ruby versions < 1.7.2 cannot inline aliased methods"
	at_exit {
	  $stderr.puts "NOTE: you ran a REALLY slow version of #{mymethod} #{$RUBY_INLINE_COMPAT} times."
	  $stderr.puts "NOTE: Upgrade to 1.7.2 or greater."
	}

      end
      $RUBY_INLINE_COMPAT += 1
      myclass.class_eval("alias_method :#{mymethod}, :_#{mymethod}")
    end    

    # Calling
    return method("_#{mymethod}").call(*args)
  end # def inline

end # module Inline

class Module

  # FIX: this has been modified to be 1.6 specific... 1.7 has better
  # options for longs

  @@type_map = {
    'char'         => [ 'NUM2CHR',  'CHR2FIX' ],
    'unsigned'     => [ 'NUM2UINT', 'UINT2NUM' ],
    'unsigned int' => [ 'NUM2UINT', 'UINT2NUM' ],
    'char *'       => [ 'STR2CSTR', 'rb_str_new2' ],
    
    # slower versions:
    #define INT2NUM(v)
    #define NUM2INT(x)
    'int'  => [ 'FIX2INT', 'INT2FIX' ],
    
    # not sure - faster, but could overflow?
    #define FIX2LONG(x)
    #define LONG2FIX(i)
    'long' => [ 'NUM2INT', 'INT2NUM' ],

    # not sure
    #define FIX2ULONG(x)
    'unsigned long' => [ 'NUM2UINT', 'UINT2NUM' ],

    # Can't do these converters
    #define ID2SYM(x)
    #define SYM2ID(x)
    #define NUM2DBL(x)
    #define FIX2UINT(x)
  }

  def ruby2c(type)
    return @@type_map[type].first
  end
#  module_function :ruby2c

  def c2ruby(type)
    return @@type_map[type].last
  end
#  module_function :c2ruby

  def parse_signature(src)

    sig = src.dup

    # strip c-comments
    sig.gsub!(/(?:(?:\/\*)(?:(?:(?!\*\/)[\s\S])*)(?:\*\/))/, '')
    # strip cpp-comments
    sig.gsub!(/(?:\/\*(?:(?!\*\/)[\s\S])*\*\/|\/\/[^\n]*\n)/, '')
    # strip preprocessor directives
    sig.gsub!(/^\s*\#.*(\\\n.*)*/, '')
    # strip {}s
    sig.gsub!(/\{[^\}]*\}/, '{ }')
    # clean and collapse whitespace
    sig.gsub!(/\s+/, ' ')

    types = 'void|' + @@type_map.keys.map{|x| Regexp.escape(x)}.join('|')
    if /(#{types})\s*(\w+)\s*\(([^)]*)\)/ =~ sig
      return_type, function_name, arg_string = $1, $2, $3
      args = []
      arg_string.split(',').each do |arg|

	# ACK! see if we can't make this go away (FIX)
	# helps normalize into 'char * varname' form
	arg = arg.gsub(/\*/, ' * ').gsub(/\s+/, ' ').strip

	if /(#{types})\s+(\w+)\s*$/ =~ arg
	  args.push([$2, $1])
	end
      end
      return {'return' => return_type,
	  'name' => function_name,
	  'args' => args }
    end
    raise "Bad parser exception: #{sig}"
  end # def parse_signature
#  module_function :parse_signature

  def inline_c_gen(src)
    result = src.dup

    # REFACTOR: this is duplicated from above
    # strip c-comments
    result.gsub!(/(?:(?:\/\*)(?:(?:(?!\*\/)[\s\S])*)(?:\*\/))/, '')
    # strip cpp-comments
    result.gsub!(/(?:\/\*(?:(?!\*\/)[\s\S])*\*\/|\/\/[^\n]*\n)/, '')

    signature = parse_signature(src)
    function_name = signature['name']
    return_type = signature['return']

    prefix = "static VALUE t_#{function_name}(int argc, VALUE *argv, VALUE self) {\n"
    count = 0
    signature['args'].each do |arg, type|
      prefix += "#{type} #{arg} = #{ruby2c(type)}(argv[#{count}]);\n"
      count += 1
    end

    # replace the function signature (hopefully) with new signature (prefix)
    result.sub!(/[^;\/\"]+#{function_name}\s*\([^\{]+\{/, "\n" + prefix)
    result.sub!(/\A\n/, '') # strip off the \n in front in case we added it
    result.gsub!(/return\s+([^\;\}]+)/) do
      "return #{c2ruby(return_type)}(#{$1})"
    end

    return result
  end # def inline_c_gen
#  module_function :inline_c_gen

  def inline_c(src)

    rootdir = ENV['INLINEDIR'] || ENV['HOME']
    assert_dir_secure(rootdir)

    tmpdir = rootdir + "/.ruby_inline"
    unless File.directory? tmpdir then
      $stderr.puts "NOTE: creating #{tmpdir} for RubyInline" if $DEBUG
      Dir.mkdir(tmpdir, 0700)
    end
    assert_dir_secure(tmpdir)

    myclass = self
    mymethod = parse_signature(src)['name']
    mod_name = "Mod_#{myclass}_#{mymethod}"
    extension = Config::CONFIG["DLEXT"]
    so_name = "#{tmpdir}/#{mod_name}.#{extension}"  # REFACTOR

    unless File.file? so_name and File.mtime($0) < File.mtime(so_name) then
      # extracted from mkmf.rb
      srcdir  = Config::CONFIG["srcdir"]
      archdir = Config::CONFIG["archdir"]
      if File.exist? archdir + "/ruby.h"
	hdrdir = archdir
      elsif File.exist? srcdir + "/ruby.h"
	hdrdir = srcdir
      else
	$stderr.puts "ERROR: Can't find header files for ruby. Exiting..."
	exit 1
      end
      
      # Generating code
      src = %Q{
#include "ruby.h"

  #{inline_c_gen(src)}

  VALUE c#{mod_name};

  void Init_#{mod_name}() {
    c#{mod_name} = rb_define_module("#{mod_name}");
    rb_define_method(c#{mod_name}, "_#{mymethod}", t_#{mymethod}, -1);
  }
}

      src_name = "#{tmpdir}/#{mod_name}.c"

      # move previous version to the side if it exists
      test_cmp = false
      old_src_name = src_name + ".old"
      if test ?f, src_name then
	test_cmp = true
	File.rename src_name, old_src_name
      end

      f = File.new(src_name, "w")
      f.puts src
      f.close

      # recompile only if the files are different
      recompile = true
      if test_cmp and File::compare(old_src_name, src_name, $DEBUG) then
	recompile = false
      end

      if recompile then

	cmd = "#{Config::CONFIG['LDSHARED']} #{Config::CONFIG['CFLAGS']} -I #{hdrdir} -o #{so_name} #{src_name}"
	
	if /mswin32/ =~ RUBY_PLATFORM then
	  cmd += " -link /INCREMENTAL:no /EXPORT:Init_#{mod_name}"
	end
	
	$stderr.puts "Building #{so_name} with '#{cmd}'" if $DEBUG
	`#{cmd}`
      end
    end

    # Loading & Replacing w/ new method

    require "#{so_name}" or raise "require on #{so_name} failed"
    class_eval("include #{mod_name}")

    eval("alias_method :#{mymethod}, :_#{mymethod}")

  end # def inline_c
#  module_function :inline_c

end # Module
