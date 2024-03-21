# A Git Porcelain inside Neovim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/ellisonleao/nvim-plugin-template/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

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

#### Windows

There are no pre-packaged releases of libgit2 on Windows so the library must be built from source.

##### Install CMake and MinGW (with Chocolatey)

```powershell
#requires -RunAsAdministrator
choco install choco install cmake --installargs 'ADD_CMAKE_TO_PATH=User'
choco install mingw
```

Make sure to restart your terminal after installing MinGW to ensure that the `gcc` and `g++` commands are available.

##### Clone and build libgit2

```powershell
git clone https://github.com/libgit2/libgit2
cd libgit2
mkdir build
cd build
cmake -G "MinGW Makefiles" ..
cmake --build .
```

Now you should have a `libgit2.dll` in the `build` directory. This should be copied to a location in your `PATH` or to the same directory as your Neovim executable.

### Neovim

#### Lazy

If you are using lazy, you can use this config




```lua
{
  'SuperBo/fugit2.nvim',
  opts = {},
  dependencies = {
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons',
    'sindrets/diffview.nvim',
    'nvim-lua/plenary.nvim',
    {
      'chrisgrieser/nvim-tinygit', -- optional: for Github PR view
      dependencies = { 'stevearc/dressing.nvim' }
    },
    'sindrets/diffview.nvim' -- optional: for Diffview
  },
  cmd = { 'Fugit2', 'Fugit2Graph' },
  keys = {
    { '<leader>F', mode = 'n', '<cmd>Fugit2<cr>' }
  }
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
