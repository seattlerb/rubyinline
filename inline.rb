#!/usr/local/bin/ruby -w

##
# Ruby Inline is a framework for writing ruby extensions in foreign languages
# 
# = SYNOPSIS
#
#   require 'inline'
#   class MyClass
#     inline do |builder|
#       builder.include "<math.h>"
#       builder.c %q{
#         long factorial(int max) {
#           int i=max, result=1;
#           while (i >= 2) { result *= i--; }
#           return result;
#         }
#       }
#     end
#   end
# 
# = DESCRIPTION
# 
# DOC
#

require "rbconfig"
require "ftools"

$TESTING = false unless defined? $TESTING

##
# DOC
#

module Inline
  VERSION = '3.1.0'

  $stderr.puts "RubyInline v #{VERSION}" if $DEBUG

  def self.rootdir
    unless defined? @@rootdir and test ?d, @@rootdir then
      rootdir = ENV['INLINEDIR'] || ENV['HOME']
      Dir.mkdir rootdir, 0700 unless test ?d, rootdir
      Dir.assert_secure rootdir
      @@rootdir = rootdir
    end

    @@rootdir
  end

  def self.directory
    unless defined? @@directory and test ?d, @@directory then
      directory = rootdir + "/.ruby_inline" # TODO Dir.join
      unless File.directory? directory then
	$stderr.puts "NOTE: creating #{directory} for RubyInline" if $DEBUG
	Dir.mkdir directory, 0700
      end
      Dir.assert_secure directory
      @@directory = directory
    end
    @@directory
  end

  ##
  # DOC
  #
  
  class C 

    protected unless $TESTING

    MAGIC_ARITY_THRESHOLD = 2
    MAGIC_ARITY = -1

    @@type_map = {
      'char'          => [ 'NUM2CHR',  'CHR2FIX' ],
      'char *'        => [ 'STR2CSTR', 'rb_str_new2' ],
      'int'           => [ 'FIX2INT',  'INT2FIX' ],
      'long'          => [ 'NUM2INT',  'INT2NUM' ],
      'unsigned int'  => [ 'NUM2UINT', 'UINT2NUM' ],
      'unsigned long' => [ 'NUM2UINT', 'UINT2NUM' ],
      'unsigned'      => [ 'NUM2UINT', 'UINT2NUM' ],
      # Can't do these converters because they conflict with the above:
      # ID2SYM(x), SYM2ID(x), NUM2DBL(x), FIX2UINT(x)
    }

    def ruby2c(type)
      return @@type_map[type].first if @@type_map.has_key? type
      raise "Unknown type #{type}"
    end

    def c2ruby(type)
      return @@type_map[type].last if @@type_map.has_key? type
      raise "Unknown type #{type}"
    end

    def parse_signature(src, raw=false)
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

      if /(#{types})\s*(\w+)\s*\(([^)]*)\)/ =~ sig then
	return_type, function_name, arg_string = $1, $2, $3
	args = []
	arg_string.split(',').each do |arg|

	  # ACK! see if we can't make this go away (FIX)
	  # helps normalize into 'char * varname' form
	  arg = arg.gsub(/\s*\*\s*/, ' * ').strip

	  # if /(#{types})\s+(\w+)\s*$/ =~ arg
	  if /(((#{types})\s*\*?)+)\s+(\w+)\s*$/ =~ arg then
	    args.push([$4, $1])
	    # args.push([$2, $1])
	  elsif arg != "void" then
	    $stderr.puts "WARNING: '#{arg}' not understood"
	  end
	end

	arity = args.size
	arity = -1 if arity > MAGIC_ARITY_THRESHOLD or raw

	return {
	  'return' => return_type,
	    'name' => function_name,
	    'args' => args,
	   'arity' => arity
	}
      end

      raise "Bad parser exception: #{sig}"
    end # def parse_signature

    def generate(src, expand_types=true)
      result = src.dup

      # REFACTOR: this is duplicated from above
      # strip c-comments
      result.gsub!(/(?:(?:\/\*)(?:(?:(?!\*\/)[\s\S])*)(?:\*\/))/, '')
      # strip cpp-comments
      result.gsub!(/(?:\/\*(?:(?!\*\/)[\s\S])*\*\/|\/\/[^\n]*\n)/, '')

      signature = parse_signature(src, !expand_types)
      function_name = signature['name']
      return_type = signature['return']
      arity = signature['arity']

      if expand_types then
	prefix = "static VALUE #{function_name}("
	if arity == MAGIC_ARITY then
	  prefix += "int argc, VALUE *argv, VALUE self"
	else
	  prefix += "VALUE self"
	  signature['args'].each do |arg, type|
	    prefix += ", VALUE _#{arg}"
	  end
	end
	prefix += ") {\n"
	if arity == MAGIC_ARITY then
	  count = 0
	  signature['args'].each do |arg, type|
	    prefix += "  #{type} #{arg} = #{ruby2c(type)}(argv[#{count}]);\n"
	    count += 1
	  end
	else
	  signature['args'].each do |arg, type|
	    prefix += "  #{type} #{arg} = #{ruby2c(type)}(_#{arg});\n"
	  end
	end
	# replace the function signature (hopefully) with new signature (prefix)
	result.sub!(/[^;\/\"\>]+#{function_name}\s*\([^\{]+\{/, "\n" + prefix)
	result.sub!(/\A\n/, '') # strip off the \n in front in case we added it
	unless return_type == "void" then
	  raise "couldn't find return statement for #{function_name}" unless 
	    result =~ /return/ 
	  result.gsub!(/return\s+([^\;\}]+)/) do
	    "return #{c2ruby(return_type)}(#{$1})"
	  end
	else
	  result.sub!(/\s*\}\s*\Z/, "\nreturn Qnil;\n}")
	end
      else
	prefix = "static #{return_type} #{function_name}("
	result.sub!(/[^;\/\"\>]+#{function_name}\s*\(/, prefix)
	result.sub!(/\A\n/, '') # strip off the \n in front in case we added it
      end

      @src << result
      @sig[function_name] = arity

      return result # TODO: I only really do this for testing
    end # def generate

    def load
      # REFACTOR: mod_name and so_name should be instvars
      mod_name = "Mod_#{@mod}"
      so_name = "#{Inline.directory}/#{mod_name}.#{Config::CONFIG["DLEXT"]}"
      require "#{so_name}" or raise "require on #{so_name} failed"
      @mod.class_eval "include #{mod_name}"
    end

    def build
      mod_name = "Mod_#{@mod}"
      so_name = "#{Inline.directory}/#{mod_name}.#{Config::CONFIG["DLEXT"]}"
      rb_file = File.expand_path(caller[1].split(/:/).first) # [MS]

      unless File.file? so_name and File.mtime(rb_file) < File.mtime(so_name)
	
	src_name = "#{Inline.directory}/#{mod_name}.c"
	old_src_name = "#{src_name}.old"
	should_compare = File.write_with_backup(src_name) do |src|
	  src << %Q^\n#include "ruby.h"\n\n#{@src.join("\n\n")}\n\n  VALUE c#{mod_name};\n#ifdef __cplusplus\nextern "C" \{\n#endif\n  void Init_#{mod_name}() \{\n    c#{mod_name} = rb_define_module("#{mod_name}");\n^
	  @sig.keys.sort.each do |name|
	    arity = @sig[name]
	    src << %Q{    rb_define_method(c#{mod_name}, "#{name}", (VALUE(*)(ANYARGS))#{name}, #{arity});\n}
	  end
	  src << "\n  \}\n#ifdef __cplusplus\n\}\n#endif\n"
	end

	# recompile only if the files are different
	recompile = true
	if should_compare and File::compare(old_src_name, src_name, $DEBUG) then
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
	  if File.exist? archdir + "/ruby.h" then
	    hdrdir = archdir
	  elsif File.exist? srcdir + "/ruby.h" then
	    hdrdir = srcdir
	  else
	    $stderr.puts "ERROR: Can't find header files for ruby. Exiting..."
	    exit 1
	  end

	  flags = @flags.join(' ')
	  flags += " #{$INLINE_FLAGS}" if defined? $INLINE_FLAGS# DEPRECATE
	  libs  = @libs.join(' ')
	  libs += " #{$INLINE_LIBS}" if defined? $INLINE_LIBS	# DEPRECATE

	  cmd = "#{Config::CONFIG['LDSHARED']} #{flags} #{Config::CONFIG['CFLAGS']} -I #{hdrdir} -o #{so_name} #{src_name} #{libs}"
	  
	  if /mswin32/ =~ RUBY_PLATFORM then
	    cmd += " -link /INCREMENTAL:no /EXPORT:Init_#{mod_name}"
	  end
	  
	  $stderr.puts "Building #{so_name} with '#{cmd}'" if $DEBUG
	  `#{cmd}`
	  raise "error executing #{cmd}: #{$?}" if $? != 0
	  $stderr.puts "Built successfully" if $DEBUG
	end

      else
	$stderr.puts "#{so_name} is up to date" if $DEBUG
      end # unless (file is out of date)
    end # def build
      
    attr_accessor :mod, :src, :sig, :flags, :libs if $TESTING

    public

    ##
    # 
    #
    
    def initialize(mod)
      @mod = mod
      @src = []
      @sig = {}
      @flags = []
      @libs = []
    end

    ##
    # Adds compiler options to the compiler command line. 
    # No preprocessing is done, so you must have all your dashes and everything.
    #
    
    def add_compile_flags(*flags)
      @flags.push(*flags)
    end

    ##
    # Adds linker flags to the link command line.
    # No preprocessing is done, so you must have all your dashes and everything.
    #
    
    def add_link_flags(*flags)
      @libs.push(*flags)
    end

    ##
    # Registers C type-casts <tt>r2c</tt> and <tt>c2r</tt> for <tt>type</tt>.
    #
    
    def add_type_converter(type, r2c, c2r)
      $stderr.puts "WARNING: overridding #{type}" if @@type_map.has_key? type
      @@type_map[type] = [r2c, c2r]
    end

    ##
    # DOC
    #
    
    def include(header)
      @src << "#include #{header}"
    end

    ##
    # DOC
    #
    
    def prefix(code)
      @src << code
    end

    ##
    # DOC
    #
    
    def c src
      self.generate(src)
    end
    
    ##
    # DOC
    #
    
    def c_raw src
      self.generate(src, false)
    end

  end # class Inline::C
end # module Inline

##
# DOC
#
  
class Module

  ##
  # DOC
  #
  
  def inline(lang = :C, testing=false)
    require "inline/#{lang}" unless lang == :C
    builder = Inline.const_get(lang).new self

    yield builder

    unless testing then
      builder.build
      builder.load
    end
  end
end

##
# DOC
#
  
class File

  ##
  # DOC
  #
  
  def self.write_with_backup(path) # returns true if file already existed
    
    # if yield throws an exception, we skip the rename & writes
    data = []; yield(data); text = data.join('')

    # move previous version to the side if it exists
    renamed = false
    if test ?f, path then
      renamed = true
      File.rename path, path + ".old"
    end
    f = File.new(path, "w")
    f.puts text
    f.close

    return renamed
  end
end

##
# DOC
#
  
class Dir

  ##
  # DOC
  #
  
  def self.assert_secure(path)
    mode = File.stat(path).mode
    unless ((mode % 01000) & 0022) == 0 then # WARN: POSIX systems only...
      if $TESTING then
	raise 'InsecureDir'
      else
	$stderr.puts "#{path} is insecure (#{sprintf('%o', mode)}), needs 0700 for perms"
	exit 1
      end
    end
  end
end
