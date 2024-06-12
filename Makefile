.PHONY: test format

test:
	luarocks test --local -- --config-file=nlua.busted

format:
	stylua lua
	stylua spec
