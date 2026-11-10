" SPDX-License-Identifier: ISC
" SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>

let &runtimepath .= ',' . getcwd() . '/.config/nvim'

augroup local_quicksort
  autocmd!
  autocmd BufNewFile,BufRead *.qs setfiletype qs
augroup END
