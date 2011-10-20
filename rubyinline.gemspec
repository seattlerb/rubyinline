# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{RubyInline}
  s.version = "3.11.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Ryan Davis"]
  s.date = %q{2011-10-20}
  s.description = %q{Inline allows you to write foreign code within your ruby code. It
automatically determines if the code in question has changed and
builds it only when necessary. The extensions are then automatically
loaded into the class/module that defines it.

You can even write extra builders that will allow you to write inlined
code in any language. Use Inline::C as a template and look at
Module#inline for the required API.}
  s.email = ["ryand-ruby@zenspider.com"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt", "README.txt"]
  s.files = ["History.txt", "Manifest.txt", "README.txt", "Rakefile", "demo/fastmath.rb", "demo/hello.rb", "example.rb", "example2.rb", "lib/inline.rb", "test/test_inline.rb", "tutorial/example1.rb", "tutorial/example2.rb", ".gemtest"]
  s.homepage = %q{http://www.zenspider.com/ZSS/Products/RubyInline/}
  s.rdoc_options = ["--main", "README.txt"]
  s.require_paths = ["lib"]
  s.requirements = ["A POSIX environment and a compiler for your language."]
  s.rubyforge_project = %q{rubyinline}
  s.rubygems_version = %q{1.5.1}
  s.summary = %q{Inline allows you to write foreign code within your ruby code}
  s.test_files = ["test/test_inline.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<hoe>, ["~> 2.12"])
    else
      s.add_dependency(%q<hoe>, ["~> 2.12"])
    end
  else
    s.add_dependency(%q<hoe>, ["~> 2.12"])
  end
end