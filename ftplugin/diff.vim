"" Reference from https://vim.fandom.com/wiki/Folding_for_diff_files

" setlocal foldmethod=expr foldexpr=Fugit2DiffFold(v:lnum)

function! Fugit2DiffFold(lnum)
  let line = getline(a:lnum)
  if line =~ '^\(diff\|index\) '
    return 0
  elseif line =~ '^\(---\|+++\|@@\) '
    return 1
  elseif line[0] =~ '[-+ ]'
    return 2
  else
    return 0
  endif
endfunction
