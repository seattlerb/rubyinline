require "rbconfig"
require "ftools"

$TESTING = false unless defined? $TESTING

def assert_dir_secure(path)
  mode = File.stat(path).mode
  unless ((mode % 01000) & 0022) == 0 then # WARN: POSIX systems only...
    $stderr.puts "#{path} is insecure (#{sprintf('%o', mode)}), needs 0700 for perms" 
    exit 1
  end
end
public :assert_dir_secure

INLINE_VERSION = '2.1.2'

class Module
  private ############################################################

  # FIX: this has been modified to be 1.6 specific... 
  # 1.7 has better options for longs

  @@type_map = {
    'char'         => [ 'NUM2CHR',  'CHR2FIX' ],
    'unsigned'     => [ 'NUM2UINT', 'UINT2NUM' ],
    'unsigned int' => [ 'NUM2UINT', 'UINT2NUM' ],
    'char *'       => [ 'STR2CSTR', 'rb_str_new2' ],
    
    'int'  => [ 'FIX2INT', 'INT2FIX' ],
    
    'long' => [ 'NUM2INT', 'INT2NUM' ],

    'unsigned long' => [ 'NUM2UINT', 'UINT2NUM' ],

    # Can't do these converters:
    # ID2SYM(x), SYM2ID(x), NUM2DBL(x), FIX2UINT(x)
  }

  def ruby2c(type)
    if @@type_map.has_key?(type) then
      return @@type_map[type].first
    else
      raise "Unknown type #{type}"
    end
  end

  def c2ruby(type)
    if @@type_map.has_key?(type) then
      return @@type_map[type].last
    else
      raise "Unknown type #{type}"
    end
  end

  public if $TESTING ##################################################

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

    types = 'void|VALUE|' + @@type_map.keys.map{|x| Regexp.escape(x)}.join('|')

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

  def inline_c_gen(src, expand_types=true)
    result = src.dup

    # REFACTOR: this is duplicated from above
    # strip c-comments
    result.gsub!(/(?:(?:\/\*)(?:(?:(?!\*\/)[\s\S])*)(?:\*\/))/, '')
    # strip cpp-comments
    result.gsub!(/(?:\/\*(?:(?!\*\/)[\s\S])*\*\/|\/\/[^\n]*\n)/, '')

    signature = parse_signature(src)
    function_name = signature['name']
    return_type = signature['return']

    new_signature = "static VALUE #{function_name}(int argc, VALUE *argv, VALUE self) {\n"
    prefix = new_signature.dup

    if expand_types then

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
    else
      result.sub!(/[^;\/\"]+#{function_name}\s*\([^\{]+\{/, "\n" + new_signature)
      result.sub!(/\A\n/, '') # strip off the \n in front in case we added it
    end
    return result
  end # def inline_c_gen

  def inline_c_real(src, expand_types=false)
    rootdir = ENV['INLINEDIR'] || ENV['HOME']

    # ensure that this is a semi-secure environment...
    assert_dir_secure(rootdir)
    tmpdir = rootdir + "/.ruby_inline"
    unless File.directory? tmpdir then
      $stderr.puts "NOTE: creating #{tmpdir} for RubyInline" if $DEBUG
      Dir.mkdir(tmpdir, 0700)
    end
    assert_dir_secure(tmpdir)

    mymethod = parse_signature(src)['name']
    mod_name = "Mod_#{self}_#{mymethod}"
    so_name = "#{tmpdir}/#{mod_name}.#{Config::CONFIG["DLEXT"]}"
    rb_file = File.expand_path(caller[1].split(/:/).first) # [MS]

    unless File.file? so_name and File.mtime(rb_file) < File.mtime(so_name)

      # Generating code
      src = %Q{
#include "ruby.h"

  #{inline_c_gen(src, expand_types)}

  VALUE c#{mod_name};

  void Init_#{mod_name}() {
    c#{mod_name} = rb_define_module("#{mod_name}");
    rb_define_method(c#{mod_name}, "#{mymethod}", #{mymethod}, -1);
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

	# Updates the timestamps on all the generated/compiled files.
	# Prevents us from entering this conditional unless the source
	# file changes again.
        File.utime(Time.now, Time.now, src_name, old_src_name, so_name)
      end

      if recompile then

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

	cmd = "#{Config::CONFIG['LDSHARED']} #{Config::CONFIG['CFLAGS']} -I #{hdrdir} -o #{so_name} #{src_name}"
	
	if /mswin32/ =~ RUBY_PLATFORM then
	  cmd += " -link /INCREMENTAL:no /EXPORT:Init_#{mod_name}"
	end
	
	$stderr.puts "Building #{so_name} with '#{cmd}'" if $DEBUG
	`#{cmd}`
	raise "error executing #{cmd}: #{$?}" if $? != 0
      end
    else
      $stderr.puts "#{so_name} is up to date" if $DEBUG
    end

    # Loading new method
    require "#{so_name}" or raise "require on #{so_name} failed"
    class_eval("include #{mod_name}")

  end # inline_c_real

  public ############################################################

  def inline_c_raw(src)
    inline_c_real(src, false)
  end

  def inline_c(src)
    inline_c_real(src, true)
  end # def inline_c

end # Module
