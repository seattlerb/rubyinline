#!/usr/local/bin/ruby -w

require "inline"

############################################################
# DEPRECATED: Remove by version 3.1 or 2003-03-01
#
# This file is only provided for those who require backwards compatibility with version 2.x.
# If you don't need it, don't use it. If you do, please heed the deprecation warnings and
# migrate to the new system as fast as you can. Thanks...

module Inline
  class C 

    $INLINE_FLAGS = nil
    $INLINE_LIBS  = nil

    trace_var(:$INLINE_FLAGS) do |val|
      $stderr.puts "WARNING: $INLINE_FLAGS is deprecated. Use #add_link_flags. Called from #{caller[1]}."
    end

    trace_var(:$INLINE_LIBS) do |val|
      $stderr.puts "WARNING: $INLINE_LIBS is deprecated. Use #add_compile_flags. Called from #{caller[1]}."
    end
  end
end

class Module
  public

  def inline_c(src)
    $stderr.puts "WARNING: inline_c is deprecated. Switch to Inline module"
    inline(:C) do | builder |
      builder.c src
    end
  end

  def inline_c_raw(src)
    $stderr.puts "WARNING: inline_c_raw is deprecated. Switch to Inline module"
    inline(:C) do | builder |
      builder.c_raw src
    end
  end
end
