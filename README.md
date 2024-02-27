# A Git Porcelain inside Neovim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

Git plugin for Neovim (based on libgit2).

![Fugit2 Main View](https://raw.githubusercontent.com/SuperBo/fugit2.nvim/assets/assets/main_view.png)

![Fugit2 Diff View](https://raw.githubusercontent.com/SuperBo/fugit2.nvim/assets/assets/inline_patch_view.png)

![Fugit2 Graph View](https://raw.githubusercontent.com/SuperBo/fugit2.nvim/assets/assets/graph_view.png)

## ✨ Features

- ✔ Floating git source window.
- ✔ Magit style menu.
- ✔ Patch View.
- ✔ Stage/Unstage hunkes in patch view.
- ✔ Nice git graph.
- ☐ TODO: In-memory rebase.
- ☐ TODO: Diff view.

## 📦 Installation

### Libgit2

Libgit2 is required for this plugin to work. So you have to install it in your OS before starting with Fugit2.
For more information, you can refer to this https://libgit2.org/

#### Ubuntu 22.04

```sh
sudo apt-get install -y libgit2-1.1
sudo ln -s /usr/lib/x86_64-linux-gnu/libgit2.so.1.1 /usr/local/lib/libgit2.so
sudo ldconfig
```

#### Ubuntu 23.10

```sh
sudo apt-get install -y libgit2-1.5
sudo ln -s /usr/lib/x86_64-linux-gnu/libgit2.so.1.5 /usr/local/lib/libgit2.so
sudo ldconfig
```

#### Arch Linux

```sh
sudo pacman -S libgit2
```

#### Mac OS

```sh
brew install libgit2
```

### Neovim

#### Lazy

If you are using lazy, you can use this config

```lua
{
  'SuperBo/fugit2.nvim'
  opts = {},
  dependencies = {
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons',
    'nvim-lua/plenary.nvim',
    {
      'chrisgrieser/nvim-tinygit',
      dependencies = { 'stevearc/dressing.nvim' }
    }
  },
  cmd = { 'Fugit2', 'Fugit2Graph' },
  keys = {
    { '<leader>F', mode = 'n', '<cmd>Fugit2<cr>' }
  }
}
```

#### pckr.nvim

TODO: add later

## Default Keybinding and Usage

TODO: add later
