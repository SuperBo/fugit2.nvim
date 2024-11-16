![Fugit2 logo](logo.png)

# Neovim git GUI powered by libgit2

![Neovim](https://camo.githubusercontent.com/eead1ee1a978cd0b8a41e94d79973e5f84a337858ce89db1b2c2084140c35a0b/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f4e656f56696d2d2532333537413134332e7376673f267374796c653d666f722d7468652d6261646765266c6f676f3d6e656f76696d266c6f676f436f6c6f723d7768697465)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)
![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/lint-test.yml?branch=main&style=for-the-badge)

Git plugin for Neovim (based on libgit2).


![Fugit2 Main View](https://raw.githubusercontent.com/SuperBo/fugit2.nvim/assets/assets/main_view.png)
![Fugit2 Graph View](https://raw.githubusercontent.com/SuperBo/fugit2.nvim/assets/assets/graph_view.png)

## ✨ Features

- ✔ Floating git source window.
- ✔ Magit style menu.
- ✔ Patch View.
- ✔ Stage/Unstage hunkes in patch view.
- ✔ Nice git graph.
- ✔ Native branch picker.
- ✔ Diff view.
- ✔ Git blame.
- ☐ TODO: In-memory rebase.
- ☐ TODO: Remap default key binding.
- ☐ TODO: Proper help menu.

## 📦 Installation

Please [install libgit2](https://github.com/SuperBo/fugit2.nvim/wiki/Install-libgit2) before installing plugin.

[Install GPGme](https://github.com/SuperBo/fugit2.nvim/wiki/GPG-Singing-and-SSH-Signing) if you use gpg key for commit signing.

Third party libraries:
  - Required: [libgit2](https://libgit2.org)
  - Optional (if use gpg signing): [GPGme](https://gnupg.org/software/gpgme/index.html)

### Neovim

[![LuaRocks](https://img.shields.io/luarocks/v/superbo/fugit2.nvim?logo=lua&color=purple)](https://luarocks.org/modules/SuperBo/fugit2.nvim)

#### Rocks.nvim

```
:Rocks install fugit2.nvim
```

The setup function must be called before using this plugin, see [Installation Guide](https://github.com/SuperBo/fugit2.nvim/wiki/%F0%9F%93%A6-Installation#rocksnvim).

#### Lazy

If you are using lazy, you can use this config


```lua
{
  'SuperBo/fugit2.nvim',
  opts = {
    width = 100,
  },
  dependencies = {
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons',
    'nvim-lua/plenary.nvim',
    {
      'chrisgrieser/nvim-tinygit', -- optional: for Github PR view
      dependencies = { 'stevearc/dressing.nvim' }
    },
  },
  cmd = { 'Fugit2', 'Fugit2Diff', 'Fugit2Graph' },
  keys = {
    { '<leader>F', mode = 'n', '<cmd>Fugit2<cr>' }
  }
},
```

In case you want to use more stable [diffview.nvim](https://github.com/sindrets/diffview.nvim) for diff split view.

<details>

```lua
{
  'SuperBo/fugit2.nvim',
  opts = {
    width = 70,
    external_diffview = true, -- tell fugit2 to use diffview.nvim instead of builtin implementation.
  },
  dependencies = {
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons',
    'nvim-lua/plenary.nvim',
    {
      'chrisgrieser/nvim-tinygit', -- optional: for Github PR view
      dependencies = { 'stevearc/dressing.nvim' }
    },
  },
  cmd = { 'Fugit2', 'Fugit2Blame', 'Fugit2Diff', 'Fugit2Graph' },
  keys = {
    { '<leader>F', mode = 'n', '<cmd>Fugit2<cr>' }
  }
},
{
  'sindrets/diffview.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  -- lazy, only load diffview by these commands
  cmd = {
    'DiffviewFileHistory', 'DiffviewOpen', 'DiffviewToggleFiles', 'DiffviewFocusFiles', 'DiffviewRefresh'
  }
}
```

</details>

#### pckr.nvim

TODO: add later

#### Default options/setup dictionary

```lua
---@class Fugit2Config
---@field width integer|string Main popup width
---@field max_width integer|string Main popup popup width when expand patch view
---@field min_width integer File view width when expand patch view
---@field content_width File view content width
---@field height integer|string Main popup height
---@field show_patch boolean show patch for active file when open fugit2 main window
---@field libgit2_path string? path to libgit2 lib, default: "libgit2"
---@field gpgme_path string? path to gpgme lib, default: "gpgme"
---@field external_diffview boolean whether to use external diffview.nvim or Fugit2 implementation
---@field blame_priority integer priority of blame virtual text
---@field blame_info_width integer width of blame hunk detail popup
---@field blame_info_height integer height of blame hunk detail popup
---@field colorscheme string? custom color scheme override
local opts = {
  width = 100,
  min_width = 50,
  content_width = 60,
  max_width = "80%",
  height = "60%",
  external_diffview = false,
  blame_priority = 1,
  blame_info_height = 10,
  blame_info_width = 60,
  show_patch = false,
}
```

## Tested colorschemes

- [Catppuccin](https://github.com/catppuccin/nvim)
- [Nightfox](https://github.com/EdenEast/nightfox.nvim)
- [Tokyo Night](https://github.com/folke/tokyonight.nvim)
- [Kanagawa](https://github.com/rebelot/kanagawa.nvim)
- [Cyberdream](https://github.com/scottmckendry/cyberdream.nvim): please set `colorscheme = "cyberdream"` in plugin options.

## Usage and Keymap

Please refer to [Usage Guide](https://github.com/SuperBo/fugit2.nvim/wiki/%E2%8C%A8%EF%B8%8F-Usage-and-Keymap).

## Credits

Very special thanks to these plugins and their authors.

- [nvim-tiny](https://github.com/chrisgrieser/nvim-tinygit) for Github integration.
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) for Diffview integration.
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) for his great Nvim UI library.
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for utilities and testing framework.
- [libgit2](https://libgit2.org/) for lightweight and performance git library.
- [lazygit](https://github.com/jesseduffield/lazygit) for Git pane inspirations.
- [fugitive.vim](https://github.com/tpope/vim-fugitive) for a great vim git client.
- [magit](https://magit.vc/) for a great Git client.
- [neogit](https://github.com/NeogitOrg/neogit) for great Neovim git client.
- [vim-flog](https://github.com/rbong/vim-flog) for beautiful git graph.
- [blame.nvim](https://github.com/FabijanZulj/blame.nvim) for git blame inspiration.
