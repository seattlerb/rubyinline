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

module Inline

  VERSION = '1.1.0'

  # TODO: extend the signature to pass in self in order to zap aliased methods
  # def inline(args, prelude, src=nil, instance=self)
  def inline(args, prelude, src=nil)

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

    myclass = self.class
    mymethod = self.caller_method_name
    mod_name = "Mod_#{myclass}_#{mymethod}"
    so_name = "#{tmpdir}/#{mod_name}.so"

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
      $stderr.puts "WARNING: ruby versions < 1.7.2 cannot inline aliased methods"
      myclass.class_eval("alias_method :#{mymethod}, :_#{mymethod}")
    end    

    # Calling
    return method("_#{mymethod}").call(*args)
  end
end
