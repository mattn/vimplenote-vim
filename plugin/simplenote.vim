"=============================================================================
" File: vimplenote.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 16-Nov-2011.
" Version: 0.1
" WebPage: http://github.com/mattn/vimplenote-vim
" License: BSD
" Usage:
"
"   :VimpleNote -D => delete note in current buffer
"   :VimpleNote -d => move note to trash
"   :VimpleNote -l => list all notes
"   :VimpleNote -n => create new note from buffer
"   :VimpleNote -t => tag note in current buffer
"   :VimpleNote -u => update a note from buffer

if &cp || (exists('g:loaded_vimplenote_vim') && g:loaded_vimplenote_vim)
  finish
endif
let g:loaded_vimplenote_vim = 1

command! -nargs=1 -range VimpleNote :call vimplenote#VimpleNote(<f-args>)
