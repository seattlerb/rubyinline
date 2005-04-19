#!/usr/local/bin/ruby -w

# Ruby Inline is a framework for writing ruby extensions in foreign
# languages
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
# Inline allows you to write C/C++ code within your ruby code. It
# automatically determines if the code in question has changed and
# builds it only when necessary. The extensions are then automatically
# loaded into the class/module that defines it.
#
# You can even write extra builders that will allow you to write
# inlined code in any language. Use Inline::C as a template and look
# at Module#inline for the required API.

require "rbconfig"
require "ftools"
require "digest/md5"

$TESTING = false unless defined? $TESTING

class CompilationError < RuntimeError; end

# The Inline module is the top-level module used. It is responsible
# for instantiating the builder for the right language used,
# compilation/linking when needed, and loading the inlined code into
# the current namespace.

module Inline
  VERSION = '3.2.0'

  $stderr.puts "RubyInline v #{VERSION}" if $DEBUG

  protected

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
      directory = File.join(rootdir, ".ruby_inline")
      unless File.directory? directory then
	$stderr.puts "NOTE: creating #{directory} for RubyInline" if $DEBUG
	Dir.mkdir directory, 0700
      end
      Dir.assert_secure directory
      @@directory = directory
    end
    @@directory
  end

  # Inline::C is the default builder used and the only one provided by
  # Inline. It can be used as a template to write builders for other
  # languages. It understands type-conversions for the basic types and
  # can be extended as needed.
  
  class C 

    protected unless $TESTING

    MAGIC_ARITY_THRESHOLD = 2
    MAGIC_ARITY = -1

    @@type_map = {
      'char'          => [ 'NUM2CHR',  'CHR2FIX' ],
      'char *'        => [ 'STR2CSTR', 'rb_str_new2' ],
      'double'        => [ 'NUM2DBL',  'rb_float_new' ],
      'int'           => [ 'FIX2INT',  'INT2FIX' ],
      'long'          => [ 'NUM2INT',  'INT2NUM' ],
      'unsigned int'  => [ 'NUM2UINT', 'UINT2NUM' ],
      'unsigned long' => [ 'NUM2UINT', 'UINT2NUM' ],
      'unsigned'      => [ 'NUM2UINT', 'UINT2NUM' ],
      # Can't do these converters because they conflict with the above:
      # ID2SYM(x), SYM2ID(x), NUM2DBL(x), FIX2UINT(x)
    }

    def ruby2c(type)
      raise ArgumentError, "Unknown type #{type}" unless @@type_map.has_key? type
      @@type_map[type].first
    end

    def c2ruby(type)
      raise ArgumentError, "Unknown type #{type}" unless @@type_map.has_key? type
      @@type_map[type].last
    end

    def strip_comments(src)
      # strip c-comments
      src = src.gsub(/\s*(?:(?:\/\*)(?:(?:(?!\*\/)[\s\S])*)(?:\*\/))/, '')
      # strip cpp-comments
      src.gsub!(/\s*(?:\/\*(?:(?!\*\/)[\s\S])*\*\/|\/\/[^\n]*\n)/, '')
      src
    end
    
    def parse_signature(src, raw=false)

      sig = self.strip_comments(src)
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

	  # helps normalize into 'char * varname' form
	  arg = arg.gsub(/\s*\*\s*/, ' * ').strip

	  # if /(#{types})\s+(\w+)\s*$/ =~ arg
	  if /(((#{types})\s*\*?)+)\s+(\w+)\s*$/ =~ arg then
	    args.push([$4, $1])
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

      raise SyntaxError, "Can't parse signature: #{sig}"
    end # def parse_signature

    def generate(src, options={})

      if not Hash === options then
        options = {:expand_types=>options}
      end

      expand_types = options[:expand_types]
      singleton = options[:singleton]
      result = self.strip_comments(src)

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
	  raise SyntaxError, "Couldn't find return statement for #{function_name}" unless 
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

      file, line = caller[1].split(/:/)
      result = "# line #{line.to_i - 1} \"#{file}\"\n" + result

      @src << result
      @sig[function_name] = [arity,singleton]

      return result if $TESTING
    end # def generate

    attr_accessor :mod, :src, :sig, :flags, :libs if $TESTING

    public

    def load
      require "#{@so_name}" or raise LoadError, "require on #{@so_name} failed"
    end

    def build
      rb_file = File.expand_path(caller[1].split(/:/).first) # [MS]
      so_exists = File.file? @so_name

      unless so_exists and File.mtime(@rb_file) < File.mtime(@so_name)
	
	src_name = "#{Inline.directory}/#{@mod_name}.c"
	old_src_name = "#{src_name}.old"
	should_compare = File.write_with_backup(src_name) do |io|
	  io.puts
	  io.puts "#include \"ruby.h\""
	  io.puts
	  io.puts @src.join("\n\n")
	  io.puts
	  io.puts
	  io.puts "#ifdef __cplusplus"
	  io.puts "extern \"C\" {"
	  io.puts "#endif"
	  io.puts "  void Init_#{@mod_name}() {"
          io.puts "    VALUE c = rb_cObject;"
          @mod.name.split("::").each do |n|
            io.puts "    c = rb_const_get_at(c,rb_intern(\"#{n}\"));"
          end
	  @sig.keys.sort.each do |name|
	    arity, singleton = @sig[name]
            if singleton then
              io.print "    rb_define_singleton_method(c, \"#{name}\", "
            else
	      io.print "    rb_define_method(c, \"#{name}\", "
            end
	    io.puts  "(VALUE(*)(ANYARGS))#{name}, #{arity});"
	  end
	  io.puts
	  io.puts "  }"
	  io.puts "#ifdef __cplusplus"
	  io.puts "}"
	  io.puts "#endif"
	  io.puts
	end

	# recompile only if the files are different
	recompile = true
	if so_exists and should_compare and
            File::compare(old_src_name, src_name, $DEBUG) then
	  recompile = false

	  # Updates the timestamps on all the generated/compiled files.
	  # Prevents us from entering this conditional unless the source
	  # file changes again.
          t = Time.now
	  File.utime(t, t, src_name, old_src_name, @so_name)
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

	  cmd = "#{Config::CONFIG['LDSHARED']} #{flags} #{Config::CONFIG['CFLAGS']} -I #{hdrdir} -o #{@so_name} #{src_name} #{libs}"
	  
          case RUBY_PLATFORM
          when /mswin32/ then
	    cmd += " -link /INCREMENTAL:no /EXPORT:Init_#{@mod_name}"
          when /i386-cygwin/ then
            cmd += ' -L/usr/local/lib -lruby.dll'
          end

          cmd += " 2> /dev/null" if $TESTING
	  
	  $stderr.puts "Building #{@so_name} with '#{cmd}'" if $DEBUG
	  `#{cmd}`
          if $? != 0 then
            bad_src_name = src_name + ".bad"
            File.rename src_name, bad_src_name
            raise CompilationError, "error executing #{cmd}: #{$?}\nRenamed #{src_name} to #{bad_src_name}"
          end
	  $stderr.puts "Built successfully" if $DEBUG
	end

      else
	$stderr.puts "#{@so_name} is up to date" if $DEBUG
      end # unless (file is out of date)
    end # def build
      
    attr_reader :mod
    def initialize(mod)
      @mod = mod
      if @mod then
        # Figure out which script file defined the C code
        @rb_file = File.expand_path(caller[2].split(/:/).first) # [MS]
        # Extract the basename of the script and clean it up to be 
        # a valid C identifier
        rb_script_name = File.basename(@rb_file).gsub(/[^a-zA-Z0-9_]/,'_')
        # Hash the full path to the script
        suffix = Digest::MD5.new(@rb_file).to_s[0,4]
        @mod_name = "Inline_#{@mod.name.gsub('::','__')}_#{rb_script_name}_#{suffix}"
        @so_name = "#{Inline.directory}/#{@mod_name}.#{Config::CONFIG["DLEXT"]}"
      end
      @src = []
      @sig = {}
      @flags = []
      @libs = []
    end

    # Adds compiler options to the compiler command line.  No
    # preprocessing is done, so you must have all your dashes and
    # everything.
    
    def add_compile_flags(*flags)
      @flags.push(*flags)
    end

    # Adds linker flags to the link command line.  No preprocessing is
    # done, so you must have all your dashes and everything.
    
    def add_link_flags(*flags)
      @libs.push(*flags)
    end

    # Registers C type-casts <tt>r2c</tt> and <tt>c2r</tt> for
    # <tt>type</tt>.
    
    def add_type_converter(type, r2c, c2r)
      $stderr.puts "WARNING: overridding #{type}" if @@type_map.has_key? type
      @@type_map[type] = [r2c, c2r]
    end

    # Adds an include to the top of the file. Don't forget to use
    # quotes or angle brackets.
    
    def include(header)
      @src << "#include #{header}"
    end

    # Adds any amount of text/code to the source
    
    def prefix(code)
      @src << code
    end

    # Adds a C function to the source, including performing automatic
    # type conversion to arguments and the return value. Unknown type
    # conversions can be extended by using +add_type_converter+.
    
    def c src
      self.generate(src,:expand_types=>true)
    end

    def c_singleton src
      self.generate(src,:expand_types=>true,:singleton=>true)
    end
    
    # Adds a raw C function to the source. This version does not
    # perform any type conversion and must conform to the ruby/C
    # coding conventions.
    
    def c_raw src
      self.generate(src)
    end

    def c_raw_singleton src
      self.generate(src, :singleton=>true)
    end

  end # class Inline::C
end # module Inline

class Module

  # Extends the Module class to have an inline method. The default
  # language/builder used is C, but can be specified with the +lang+
  # parameter.
  
  def inline(lang = :C, testing=false)

    begin
      builder_class = Inline.const_get(lang)
    rescue NameError
      require "inline/#{lang}"
      builder_class = Inline.const_get(lang)
    end

    builder = builder_class.new self

    yield builder

    unless testing then
      builder.build
      builder.load
    end
  end
end

class File

  # Equivalent to <tt>File::open</tt> with an associated block, but moves
  # any existing file with the same name to the side first.
  
  def self.write_with_backup(path) # returns true if file already existed
    
    # move previous version to the side if it exists
    renamed = false
    if test ?f, path then
      renamed = true
      File.rename path, path + ".old"
    end

    File.open(path, "w") do |io|
      yield(io)
    end

    return renamed
  end

end # class File

class Dir

  # +assert_secure+ checks to see that +path+ exists and has minimally
  # writable permissions. If not, it prints an error and exits. It
  # only works on +POSIX+ systems. Patches for other systems are
  # welcome.
  
  def self.assert_secure(path)
    mode = File.stat(path).mode
    unless ((mode % 01000) & 0022) == 0 then
      if $TESTING then
	raise SecurityError, "Directory #{path} is insecure"
      else
	$stderr.puts "#{path} is insecure (#{sprintf('%o', mode)}), needs 0700 for perms. Exiting."
	exit 1
      end
    end
  end
end
