" Fugit2 Commit log Vim syntax file
" Language: Fugit2 Commit log buffer

if exists("b:current_syntax")
  finish
endif

let b:current_syntax = "fugit2commitlog"

" Branch 1
syntax match branch1Line "^[│●󰍌 ├]"

" Branch 2
syntax match branch2Line "^.[ ─]\{3\}[│╮╯┤┬┴┼●]" contains=branch1Line


" Highlight color
hi def link branch1Line  Fugit2Branch1
hi def link branch2Line  Fugit2Branch2
