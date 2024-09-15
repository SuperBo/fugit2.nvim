.PHONY: test format deps

test:
	luarocks test --local -- --config-file=nlua.busted

format:
	stylua lua
	stylua spec

deps:
	luarocks install --local fugit2.nvim-scm-1.rockspec
