RUBY ?= /usr/local/bin/ruby

test:
	$(RUBY) -I. -w ./test_inline.rb

examples:
	rm -rf ~/.ruby_inline; $(RUBY) -I. -w ./example.rb
	rm -rf ~/.ruby_inline; $(RUBY) -I. -w ./example2.rb
	rm -rf ~/.ruby_inline; $(RUBY) -I. -w ./tutorial/example1.rb
	rm -rf ~/.ruby_inline; $(RUBY) -I. -w ./tutorial/example2.rb

bench:
	@echo "Running native"
	@$(RUBY) -I. ./example.rb 3 2> /dev/null
	@echo "Running primer - preloads the compiler and stuff"
	@rm -rf ~/.ruby_inline; $(RUBY) -I. ./example.rb 0 2>&1 > /dev/null
	@echo "With full builds"
	@rm -rf ~/.ruby_inline; $(RUBY) -I. ./example.rb 0 2> /dev/null
	@rm -rf ~/.ruby_inline; $(RUBY) -I. ./example.rb 1 2> /dev/null
	@rm -rf ~/.ruby_inline; $(RUBY) -I. ./example.rb 2 2> /dev/null
	@echo "Without builds"
	@$(RUBY) -I. ./example.rb 0 2> /dev/null
	@$(RUBY) -I. ./example.rb 1 2> /dev/null
	@$(RUBY) -I. ./example.rb 2 2> /dev/null

install:
	@where=`$(RUBY) -rrbconfig -e 'include Config; print CONFIG["sitelibdir"]'`; \
	echo "installing inline.rb in $$where"; \
	cp -f inline.rb $$where; \
	echo Installed

clean:
	rm -rf *~ ~/.ruby_inline
