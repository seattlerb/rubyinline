#!/usr/local/bin/ruby -w

require "rbconfig"

def caller_method_name()
  /\`([^\']+)\'/.match(caller(2).first)[1]
end
public :caller_method_name

module Inline
  def inline(args, src)

    myclass = self.class
    mymethod = self.caller_method_name
    mod_name = "Mod_#{myclass}_#{mymethod}"
    so_name = "#{mod_name}.so"

    unless test ?f, so_name and test(?M, $0) < test(?M, so_name) then
      cc = "gcc  -I /usr/local/lib/ruby/1.6/i386-freebsd4/ -shared"
      src_name = "#{mod_name}.c"
      puts "Building #{so_name}"

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
