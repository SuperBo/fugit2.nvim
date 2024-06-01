TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test

test:
	luarocks test --local

format:
	stylua lua
	stylua spec
