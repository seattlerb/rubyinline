RUBY ?= /usr/local/bin/ruby

test:
	$(RUBY) -w ./test_inline.rb

bench:
	@echo "Running native"
	@$(RUBY) ./example.rb 3 2> /dev/null
	@echo "Running primer - preloads the compiler and stuff"
	@rm -rf ~/.ruby_inline; $(RUBY) ./example.rb 0 2>&1 > /dev/null
	@echo "With full builds"
	@rm -rf ~/.ruby_inline; $(RUBY) ./example.rb 0 2> /dev/null
	@rm -rf ~/.ruby_inline; $(RUBY) ./example.rb 1 2> /dev/null
	@rm -rf ~/.ruby_inline; $(RUBY) ./example.rb 2 2> /dev/null
	@echo "Without builds"
	@$(RUBY) ./example.rb 0 2> /dev/null
	@$(RUBY) ./example.rb 1 2> /dev/null
	@$(RUBY) ./example.rb 2 2> /dev/null

install:
	@where=`$(RUBY) -rrbconfig -e 'include Config; print CONFIG["sitelibdir"]'`; \
	echo "installing inline.rb in $$where"; \
	cp -f inline.rb $$where; \
	echo Installed

clean:
	rm -rf *~ ~/.ruby_inline
