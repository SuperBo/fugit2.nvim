# A Git Porcelain inside Neovim

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
- ☐ TODO: In-memory rebase.
- ☐ TODO: Diff view.
- ☐ TODO: Remap default key binding.
- ☐ TODO: Proper help menu.
- ☐ TODO: Native branch popup.

## 📦 Installation

Third party libraries:
  - Required: [Libgit2](#libgit2)
  - Optional if use gpg signing: [GPGpme](#gpgme)


### Libgit2

<details>

<summary>How to install libgit2</summary>

Libgit2 is required for this plugin to work. So you have to install it in your OS before starting with Fugit2.
For more information, you can refer to this https://libgit2.org/

#### Ubuntu 22.04

```sh
sudo apt-get install -y libgit2-1.1
# sudo ln -s /usr/lib/x86_64-linux-gnu/libgit2.so.1.1 /usr/local/lib/libgit2.so
# sudo ldconfig
```

Set libgit2_path value in config options like this

```lua
{
  'SuperBo/fugit2.nvim',
  opts = {
    libgit2_path = 'libgit2.so.1.1',
  },
  ...
}
```

#### Ubuntu 23.10

```sh
sudo apt-get install -y libgit2-1.5
# sudo ln -s /usr/lib/x86_64-linux-gnu/libgit2.so.1.5 /usr/local/lib/libgit2.so
# sudo ldconfig
```

Set libgit2_path value in config options like this

```lua
{
  'SuperBo/fugit2.nvim',
  opts = {
    libgit2_path = 'libgit2.so.1.5',
  },
  ...
}
```

#### Ubuntu 24.04

```sh
sudo apt-get install -y libgit2-1.7
```

Set libgit2_path value in config options like this

```lua
{
  'SuperBo/fugit2.nvim',
  opts = {
    libgit2_path = 'libgit2.so.1.7',
  },
  ...
}
```

#### Arch Linux

```sh
sudo pacman -S libgit2
```

### Fedora

```sh
yum install libgit2
```

Set libgit2_path value in config options like this, change corresponding version.

```lua
{
  'SuperBo/fugit2.nvim',
  opts = {
    libgit2_path = 'libgit2.so.1.7',
  },
  ...
}
```

#### Mac OS

```sh
brew install libgit2
```

Set libgit2_path value in config options like this if normal load doesn't work

```lua
{
  'SuperBo/fugit2.nvim',
  opts = {
    libgit2_path = '/opt/homebrew/lib/libgit2.dylib',
  },
}
```

#### Windows

```powershell
choco install libgit2
```

</details>

### GPGme

<details>

<summary>How to install gpgme</summary>

If you do config enabling git gpg signing, you must install [GPGme](https://gnupg.org/software/gpgme/index.html) lib for fugit2 to work.

In addition, you should config gpg-agent to use a GUI Pinentry, so that it don't disrupt terminal when asking passphrase.

#### Mac OS

```sh
brew install gpgme pinentry-mac
echo "pinentry-program $(which pinentry-mac)" >> ~/.gnupg/gpg-agent.conf
```

#### Ubuntu/Debian

```sh
sudo apt-get install libgpgme-dev
```

### Arch Linux

```sh
sudo pacman -S gpgme
```

</details>

### Neovim

[![LuaRocks](https://img.shields.io/luarocks/v/superbo/fugit2.nvim?logo=lua&color=purple)](https://luarocks.org/modules/SuperBo/fugit2.nvim)

#### Rocks.nvim

```
:Rocks install fugit2.nvim
```

#### Lazy

If you are using lazy, you can use this config


```lua
{
  'SuperBo/fugit2.nvim',
  opts = {
    width = 70,
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
  cmd = { 'Fugit2', 'Fugit2Graph' },
  keys = {
    { '<leader>F', mode = 'n', '<cmd>Fugit2<cr>' }
  }
},
{
  -- optional: for diffview.nvim integration
  'sindrets/diffview.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  -- lazy, only load diffview by these commands
  cmd = {
    'DiffviewFileHistory', 'DiffviewOpen', 'DiffviewToggleFiles', 'DiffviewFocusFiles', 'DiffviewRefresh'
  }
}
```

Default options dictionary

```lua
---@class Fugit2Config
---@field width integer|string Main popup width
---@field max_width integer|string Main popup popup width when expand patch view
---@field min_width integer File view width when expand patch view
---@field content_width File view content width
---@field height integer|string Main popup height
local opts = {
  width = 100,
  min_width = 50,
  content_width = 60,
  max_width = "80%",
  height = "60%",
}
```

#### pckr.nvim

TODO: add later

## Keyboard and Usage

### Main Git Status View
Trigger this view by ":Fugit2" command or by any shortcut that you assigned to.

Hot keys and usages:
- `Enter`: Open current file for editting.
- `Space`: Toggle staged/unstaged of current entry.
- `-`:  Toggle staged/unstaged of current entry.
- `s`: Stage current entry.
- `u`: Unstage current entry.
- `=`: Toggle patch view of current entry.
- `x`: Discard current entry.
- `D`: Discard current entry.
- `j`: Move cursor to next entry.
- `k`: Move cursor to previous entry.
- `l`: Move cursor to patch view if visible.
- `q`: Quit view.
- `Esc`: Quite view.
- `c`: Open Commit menu.
- `b`: Open Branch menu.
- `d`: Open Diffing menu.
- `f`: Open Fetching menu.
- `p`: Open Pull menu.
- `P`: Open Push menu.
- `N`: Open Github integration menu.

### Commit Message Pane

![Fugit2 Commit Input](https://raw.githubusercontent.com/SuperBo/fugit2.nvim/assets/assets/commit_message_view.png)

Input your commit message.

Hot keys and usages:
- `Esc`: Quit current commit action.
- `q`: Quit current commit action.
- `Enter`: Finish commit message and complete current commit action.
- `Ctrl-c`: Quit current commit action while in **insert mode**.
- `Ctrl-Enter`: Finish commit message and complete current commit action while in **insert mode**.

### Git Status Patch Pane

![Fugit2 Diff View](https://raw.githubusercontent.com/SuperBo/fugit2.nvim/assets/assets/inline_patch_view.png)

Trigger Patch view by pressing "=" in main status view, then use "h", "l" to navigate between them.

Hot keys and usages:
- `=`: Toggle Patch pane view.
- `l`: Move cursor to right pane.
- `h`: Move cursor to left pane.
- `s`: Stage hunk or visual selection.
- `u`: Unstage hunk or visual selection.
- `-`: Stage if you are in Unstaged pane, Unstage if you are in Staged pane.
- `zc`: Fold current hunk.
- `zo`: Unfold current folded hunk.
- `J`: Move to next hunk.
- `K`: Move to previous hunk.

### Git Graph View

Keys and usages:

- `k`, `j`: move up and down.
- `yy`: copy commit id.
- `yc`: copy commit id to clipboard.


## Credits

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
