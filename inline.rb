#!/usr/local/bin/ruby -w

require "rbconfig"

def caller_method_name()
  /\`([^\']+)\'/.match(caller(2).first)[1]
end
public :caller_method_name

module Inline

  VERSION = '1.0.5'

  def inline(args, src)

    tmpdir = ENV['INLINEDIR'] || ENV['HOME'] + "/.ruby_inline"

    unless File.directory? tmpdir then
      $stderr.puts "NOTE: creating #{tmpdir} for RubyInline"
      Dir.mkdir(tmpdir, 0700)
    end

    mode = File.stat(tmpdir).mode
    unless (mode % 01000) == 0700 then # FIX: not platform independent.
      $stderr.printf "mode = %o\n", mode
      $stderr.puts "#{tmpdir} is insecure, needs 0700 for perms" 
      exit 1
    end

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

      cc = "#{Config::CONFIG['LDSHARED']} #{Config::CONFIG['CFLAGS']} -I #{hdrdir}"
      src_name = "#{tmpdir}/#{mod_name}.c"
      $stderr.puts "Building #{so_name} with '#{cc}'"

      s = %Q{
#include "ruby.h"

  static VALUE t_#{mymethod}(int argc, VALUE *argv, VALUE self) {
    #{src}
  }

  VALUE c#{mod_name};

  void Init_#{mod_name}() {
    c#{mod_name} = rb_define_module("#{mod_name}");
    rb_define_method(c#{mod_name}, "_#{mymethod}", t_#{mymethod}, -1);
  }
}

      # Generating code
      f = File.new(src_name, "w")
      f.puts s
      f.close

      # Compiling
      `#{cc} -o #{so_name} #{src_name}`
    end

    # Loading & Replacing w/ new method
    require "#{so_name}"
    myclass.class_eval("include #{mod_name}")
    myclass.class_eval("alias_method :old_#{mymethod}, :#{mymethod}")
    myclass.class_eval("alias_method :#{mymethod}, :_#{mymethod}")
    
    # Calling
    return method("_#{mymethod}").call(*args)
  end
end
