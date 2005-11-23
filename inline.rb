#!/usr/local/bin/ruby -w

##
# Ruby Inline is a framework for writing ruby extensions in foreign
# languages.
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
# Inline allows you to write foreign code within your ruby code. It
# automatically determines if the code in question has changed and
# builds it only when necessary. The extensions are then automatically
# loaded into the class/module that defines it.
#
# Using the package_inline tool Inline now allows you to package up
# your inlined object code for distribution to systems without a
# compiler (read: windows)!
#
# You can even write extra builders that will allow you to write
# inlined code in any language. Use Inline::C as a template and look
# at Module#inline for the required API.

require "rbconfig"
require "digest/md5"
require 'ftools'
require 'fileutils'

$TESTING = false unless defined? $TESTING

class CompilationError < RuntimeError; end

##
# The Inline module is the top-level module used. It is responsible
# for instantiating the builder for the right language used,
# compilation/linking when needed, and loading the inlined code into
# the current namespace.

module Inline
  VERSION = '3.5.0'

  $stderr.puts "RubyInline v #{VERSION}" if $DEBUG

  protected

  def self.rootdir
    env = ENV['INLINEDIR'] || ENV['HOME']
    unless defined? @@rootdir and env == @@rootdir and test ?d, @@rootdir then
      rootdir = ENV['INLINEDIR'] || ENV['HOME']
      Dir.mkdir rootdir, 0700 unless test ?d, rootdir
      Dir.assert_secure rootdir
      @@rootdir = rootdir
    end

    @@rootdir
  end

  def self.directory
    directory = File.join(rootdir, ".ruby_inline")
    unless defined? @@directory and directory == @@directory and test ?d, @@directory then
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
	# replace the function signature (hopefully) with new sig (prefix)
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

      delta = if result =~ /\A(static.*?\{)/m then
                $1.split(/\n/).size
              else
                warn "WARNING: Can't find signature in #{result.inspect}\n" unless $TESTING
                0
              end

      file, line = caller[1].split(/:/)
      result = "# line #{line.to_i + delta} \"#{file}\"\n" + result unless $DEBUG and not $TESTING

      @src << result
      @sig[function_name] = [arity,singleton]

      return result if $TESTING
    end # def generate

    def module_name
      unless defined? @module_name then
        module_name = @mod.name.gsub('::','__')
        md5 = Digest::MD5.new
        @sig.keys.sort_by{|x| x.to_s}.each { |m| md5 << m.to_s }
        @module_name = "Inline_#{module_name}_#{md5.to_s[0,4]}"
      end
      @module_name
    end

    def so_name
      unless defined? @so_name then
        @so_name = "#{Inline.directory}/#{module_name}.#{Config::CONFIG["DLEXT"]}"
      end
      @so_name
    end

    attr_reader :rb_file, :mod
    attr_accessor :mod, :src, :sig, :flags, :libs if $TESTING

    public

    def initialize(mod)
      raise ArgumentError, "Class/Module arg is required" unless Module === mod
      # new (but not on some 1.8s) -> inline -> real_caller|eval
      stack = caller
      meth = stack.shift until meth =~ /in .(inline|test_)/ or stack.empty?
      raise "Couldn't discover caller" if stack.empty?
      real_caller = stack.first
      real_caller = stack[3] if real_caller =~ /\(eval\)/
      @real_caller = real_caller.split(/:/).first
      @rb_file = File.expand_path(@real_caller)

      @mod = mod
      @src = []
      @sig = {}
      @flags = []
      @libs = []
      @init_extra = []
    end

    ##
    # Attempts to load pre-generated code returning true if it succeeds.

    def load_cache
      begin
        file = File.join("inline", File.basename(so_name))
        if require file then
          dir = Inline.directory
          warn "WARNING: #{dir} exists but is not being used" if test ?d, dir
          return true
        end
      rescue LoadError
      end
      return false
    end

    ##
    # Loads the generated code back into ruby

    def load
      require "#{so_name}" or raise LoadError, "require on #{so_name} failed"
    end

    ##
    # Builds the source file, if needed, and attempts to compile it.

    def build
      so_name = self.so_name
      so_exists = File.file? so_name

      unless so_exists and File.mtime(rb_file) < File.mtime(so_name)
	
	src_name = "#{Inline.directory}/#{module_name}.c"
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
	  io.puts "  void Init_#{module_name}() {"
          io.puts "    VALUE c = rb_cObject;"
          # TODO: use rb_class2path
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

          io.puts @init_extra.join("\n") unless @init_extra.empty?

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
	  File.utime(t, t, src_name, old_src_name, so_name)
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
	  
          case RUBY_PLATFORM
          when /mswin32/ then
	    cmd += " -link /INCREMENTAL:no /EXPORT:Init_#{module_name}"
          when /i386-cygwin/ then
            cmd += ' -L/usr/local/lib -lruby.dll'
          end

          cmd += " 2> /dev/null" if $TESTING and not $DEBUG
	  
	  $stderr.puts "Building #{so_name} with '#{cmd}'" if $DEBUG
          `#{cmd}`
          if $? != 0 then
            bad_src_name = src_name + ".bad"
            File.rename src_name, bad_src_name
            raise CompilationError, "error executing #{cmd}: #{$?}\nRenamed #{src_name} to #{bad_src_name}"
          end
	  $stderr.puts "Built successfully" if $DEBUG
	end

      else
	$stderr.puts "#{so_name} is up to date" if $DEBUG
      end # unless (file is out of date)
    end # def build
      
    ##
    # Adds compiler options to the compiler command line.  No
    # preprocessing is done, so you must have all your dashes and
    # everything.
    
    def add_compile_flags(*flags)
      @flags.push(*flags)
    end

    ##
    # Adds linker flags to the link command line.  No preprocessing is
    # done, so you must have all your dashes and everything.
    
    def add_link_flags(*flags)
      @libs.push(*flags)
    end

    ##
    # Adds custom content to the end of the init function.

    def add_to_init(*src)
      @init_extra.push(*src)
    end

    ##
    # Registers C type-casts +r2c+ and +c2r+ for +type+.
    
    def add_type_converter(type, r2c, c2r)
      $stderr.puts "WARNING: overridding #{type}" if @@type_map.has_key? type
      @@type_map[type] = [r2c, c2r]
    end

    ##
    # Adds an include to the top of the file. Don't forget to use
    # quotes or angle brackets.
    
    def include(header)
      @src << "#include #{header}"
    end

    ##
    # Adds any amount of text/code to the source
    
    def prefix(code)
      @src << code
    end

    ##
    # Adds a C function to the source, including performing automatic
    # type conversion to arguments and the return value. Unknown type
    # conversions can be extended by using +add_type_converter+.
    
    def c src
      self.generate(src,:expand_types=>true)
    end

    ##
    # Same as +c+, but adds a class function.
    
    def c_singleton src
      self.generate(src,:expand_types=>true,:singleton=>true)
    end
    
    ##
    # Adds a raw C function to the source. This version does not
    # perform any type conversion and must conform to the ruby/C
    # coding conventions.
    
    def c_raw src
      self.generate(src)
    end

    ##
    # Same as +c_raw+, but adds a class function.
    
    def c_raw_singleton src
      self.generate(src, :singleton=>true)
    end

  end # class Inline::C

  class Packager
    attr_accessor :name, :version, :summary, :libs_copied, :inline_dir

    def initialize(name, version, summary = '')
      @name = name
      @version = version
      @summary = summary
      @libs_copied = false
      @ext = Config::CONFIG['DLEXT']

      # TODO (maybe) put libs in platform dir
      @inline_dir = File.join "lib", "inline"
    end

    def package
      copy_libs
      generate_rakefile
      build_gem
    end

    def copy_libs
      unless @libs_copied then
        FileUtils.mkdir_p @inline_dir
        built_libs = Dir.glob File.join(Inline.directory, "*.#{@ext}")
        FileUtils.cp built_libs, @inline_dir
        @libs_copied = true
      end
    end

    def generate_rakefile
      if File.exists? 'Rakefile' then
        unless $TESTING then
          STDERR.puts "Hrm, you already have a Rakefile, so I didn't touch it."
          STDERR.puts "You might have to add the following files to your gemspec's files list:"
          STDERR.puts "\t#{gem_libs.join "\n\t"}"
        end
        return
      end

      rakefile = eval RAKEFILE_TEMPLATE 

      STDERR.puts "==> Generating Rakefile" unless $TESTING
      File.open 'Rakefile', 'w' do |fp|
        fp.puts rakefile
      end
    end

    def build_gem
      STDERR.puts "==> Running rake" unless $TESTING or $DEBUG

      cmd = "rake package"
      cmd += "> /dev/null 2> /dev/null" if $TESTING unless $DEBUG
      system cmd

      STDERR.puts unless $TESTING
      STDERR.puts "Ok, you now have a gem in ./pkg, enjoy!" unless $TESTING
    end

    def gem_libs
      unless defined? @gem_libs then
        @gem_libs = Dir.glob File.join(@inline_dir, "*.#{@ext}")
        files = Dir.glob(File.join('lib', '*')).select { |f| test ?f, f }
        
        @gem_libs.push(*files)
        @gem_libs.sort!
      end
      @gem_libs
    end

    RAKEFILE_TEMPLATE = '%[require "rake"\nrequire "rake/gempackagetask"\n\nsummary = #{summary.inspect}\n\nif summary.empty? then\n  STDERR.puts "*************************************"\n  STDERR.puts "*** Summary not filled in, SHAME! ***"\n  STDERR.puts "*************************************"\nend\n\nspec = Gem::Specification.new do |s|\n  s.name = #{name.inspect}\n  s.version = #{version.inspect}\n  s.summary = summary\n\n  s.has_rdoc = false\n  s.files = #{gem_libs.inspect}\n  s.add_dependency "RubyInline", ">= 3.3.0"\n  s.require_path = "lib"\nend\n\ndesc "Builds a gem with #{name} in it"\nRake::GemPackageTask.new spec do |pkg|\n  pkg.need_zip = false\n  pkg.need_tar = false\nend\n]'
  end # class Packager
end # module Inline

class Module

  ##
  # options is a hash that allows you to pass extra data to your
  # builder.  The only key that is guaranteed to exist is :testing.

  attr_reader :options

  ##
  # Extends the Module class to have an inline method. The default
  # language/builder used is C, but can be specified with the +lang+
  # parameter.
  
  def inline(lang = :C, options={})
    case options
    when TrueClass, FalseClass then
      warn "WARNING: 2nd argument to inline is now a hash, changing to {:testing=>#{options}}" unless options
      options = { :testing => options  }
    when Hash
      options[:testing] ||= false
    else
      raise ArgumentError, "BLAH"
    end

    builder_class = begin
                      Inline.const_get(lang)
                    rescue NameError
                      require "inline/#{lang}"
                      Inline.const_get(lang)
                    end

    @options = options
    builder = builder_class.new self

    yield builder

    unless options[:testing] then
      unless builder.load_cache then
        builder.build
        builder.load
      end
    end
  end
end

class File

  ##
  # Equivalent to +File::open+ with an associated block, but moves
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

  ##
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
