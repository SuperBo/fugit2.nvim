package	= 'fugit2.nvim'

version	= 'scm-1'

rockspec_format = '3.0'

source	= {
	url	= 'git://github.com/SuperBo/fugit2.nvim.git'
}

description	= {
  summary	= 'Git plugin for Neovim (based on libgit2)',
	homepage	= 'https://github.com/SuperBo/fugit2.nvim',
	license	= 'MIT',
}

dependencies = {
  'lua>=5.1',
  'nui.nvim',
  'nvim-web-devicons',
  'plenary.nvim',
}

test_dependencies = {
  'nlua>=0.2.0',
  'busted>=2.2.0',
}

external_dependencies = {
	GIT2 = {
		library = 'git2',
	}
}

build	= {
	type = 'builtin',
  copy_directories = {
    'doc',
    'plugin',
    'ftplugin',
  },
}
