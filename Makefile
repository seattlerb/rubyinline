RUBY ?= ruby17

bench:
	@echo "Running native"
	@$(RUBY) ./example.rb 2 2> /dev/null
	@echo "Running primer"
	@rm -rf ~/.ruby_inline; $(RUBY) ./example.rb 0 2>&1 > /dev/null
	@echo "With full builds"
	@rm -rf ~/.ruby_inline; $(RUBY) ./example.rb 0 2> /dev/null
	@rm -rf ~/.ruby_inline; $(RUBY) ./example.rb 1 2> /dev/null
	@echo "Without builds"
	@$(RUBY) ./example.rb 0 2> /dev/null
	@$(RUBY) ./example.rb 1 2> /dev/null
