TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test

test:
	luarocks test --local -- --config-file=nlua.busted

format:
	stylua lua
	stylua spec
