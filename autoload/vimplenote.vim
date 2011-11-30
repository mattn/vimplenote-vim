"=============================================================================
" vimplenote.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 30-Nov-2011.

let s:save_cpo = &cpo
set cpo&vim

if !exists('s:interface')
  let s:interface = {
  \ "token": "",
  \ "email": "",
  \ "notes": [],
  \}
endif

function! s:interface.set_scratch_buffer()
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal buflisted
  setlocal cursorline
  setlocal filetype=markdown
endfunction

function! s:interface.get_current_note()
  let mx = '^VimpleNote:\zs\w\+'
  let key = matchstr(bufname('%'), mx)
  if len(key) == 0
    return {}
  endif
  let found = filter(copy(self.notes), 'v:val.key == key')
  if len(found) == 0
   return
  endif
  return found[0]
endfunction

function! s:interface.open_scratch_buffer(name)
  let bn = bufnr(a:name)
  if bn == -1
    silent noautocmd exe "new " . a:name
  else
    let bw = bufwinnr(bn)
    if bw != -1
      if winnr() != bw
        exe bw . "wincmd w"
      endif
    else
      exe "split +buffer" . bn
    endif
  endif
  call self.set_scratch_buffer()
  redraw
endfunction

function! s:interface.authorization() dict
  if len(self.token) > 0
    return ''
  endif
  let self.email = input('email:')
  let password = inputsecret('password:')
  let creds = base64#b64encode(printf('email=%s&password=%s', self.email, password))
  let res = http#post('https://simple-note.appspot.com/api/login', creds)
  if res.header[0] == 'HTTP/1.1 200 OK'
    let self.token = res.content
    return ''
  endif
  return 'VimpleNote: Failed to authenticate'
endfunction

function! s:GetNoteToCurrentBuffer(flag)
  call s:interface.display_note_in_scratch_buffer(a:flag)
endfunction

function! s:interface.list_note_index_in_scratch_buffer() dict
  if len(self.authorization())
    return
  endif

  let url = printf('https://simple-note.appspot.com/api2/index?auth=%s&email=%s&length=%d&offset=%d', self.token, http#encodeURI(self.email), 20, get(b:, "offset"))
  let res = http#get(url)
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  let datas = json#decode(res.content)
  for note in datas.data
    if !note.deleted
      if len(filter(copy(self.notes), 'v:val.key == note.key')) > 0
        continue
      endif

      let url = printf('https://simple-note.appspot.com/api2/data/%s?auth=%s&email=%s', note.key, self.token, http#encodeURI(self.email))
      let res = http#get(url)
      if res.header[0] != 'HTTP/1.1 200 OK'
        echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
        return
      endif
      let data = json#decode(res.content)
      let lines = split(data.content, "\n")
      call add(self.notes, {
      \  "title": len(lines) > 0 ? lines[0] : '',
      \  "tags": note.tags,
      \  "key": note.key,
      \  "modifydate": note.modifydate,
      \  "deleted": note.deleted,
      \})
    endif
  endfor

  call self.open_scratch_buffer("==VimpleNote==")
  silent %d _
  call setline(1, map(filter(copy(self.notes), 'v:val["deleted"] == 0'), 'printf("%s [%s]", strftime("%Y/%m/%d %H:%M:%S", v:val.modifydate), matchstr(v:val.title, "^.*\\%<60c"))'))
  nnoremap <buffer> <cr> :call <SID>GetNoteToCurrentBuffer(1)<cr>
  setlocal nomodified
endfunction

function! s:interface.search_notes_with_tags(...) dict
  if len(self.authorization())
    return
  endif

  let url = printf('https://simple-note.appspot.com/api/search?auth=%s&email=%s&query=%s', self.token, http#encodeURI(self.email), http#encodeURI(join(a:000, ' ')))
  let res = http#get(url)
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  let datas = json#decode(res.content)
  call self.open_scratch_buffer("==VimpleNote==")
  silent %d _
  call setline(1, map(datas.Response.Results, 'printf("%s | [%s]", v:val.key, matchstr(substitute(v:val.content, "\n", " ", "g"), "^.*\\%<60c"))'))
  nnoremap <buffer> <cr> :call <SID>GetNoteToCurrentBuffer(0)<cr>
  setlocal nomodified
endfunction

function! s:UpdateNoteFromCurrentBuffer()
  call s:interface.update_note_from_current_buffer()
endfunction

function! s:interface.display_note_in_scratch_buffer(flag) dict
  if len(self.authorization())
    return
  endif
  if line('.') == 0 || getline('.') == ''
    return
  endif
  if a:flag
    let note = self.notes[line('.')-1]
  else
    let note = { "key" : matchstr(getline('.'), '^[^ ]\+\ze') }
  endif
  let url = printf('https://simple-note.appspot.com/api2/data/%s?auth=%s&email=%s', note.key, self.token, http#encodeURI(self.email))
  let res = http#get(url)
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  let content = json#decode(res.content).content

  call self.open_scratch_buffer(printf("VimpleNote:%s", note.key))
  let old_undolevels = &undolevels
  set undolevels=-1
  silent! %d _
  setlocal nocursorline
  set buftype=acwrite
  silent! call setline(1, split(content, "\n"))
  au! BufWriteCmd <buffer> call <SID>UpdateNoteFromCurrentBuffer()
  setlocal nomodified
  let &undolevels = old_undolevels
endfunction

function! s:interface.create_new_note_from_current_buffer() dict
  if len(self.authorization())
    return
  endif

  let url = printf('https://simple-note.appspot.com/api2/data?auth=%s&email=%s', self.token, http#encodeURI(self.email))
  let res = http#post(url,
  \  http#encodeURI(iconv(json#encode({
  \    'content': join(getline(1, line('$')), "\n"),
  \  }), 'utf-8', &encoding))
  \)
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  let note = json#decode(res.content)
  let note.title = getline(1)
  call insert(self.notes, note)

  redraw
  echo "VimpleNote: Created successful."
  call self.set_scratch_buffer()
  setlocal nocursorline
  set buftype=acwrite
  silent exe "file" printf('VimpleNote:%s', note.key)
  au! BufWriteCmd <buffer> call <SID>UpdateNoteFromCurrentBuffer()
  setlocal nomodified
endfunction

function! s:interface.update_note_from_current_buffer() dict
  let note = self.get_current_note()
  if empty(note)
    return
  endif

  if len(self.authorization())
    return
  endif

  let url = printf('https://simple-note.appspot.com/api2/data/%s?auth=%s&email=%s', note.key, self.token, http#encodeURI(self.email))
  let res = http#post(url,
  \  http#encodeURI(iconv(json#encode({
  \    'content': join(getline(1, line('$')), "\n"),
  \    'tags': note.tags,
  \  }), 'utf-8', &encoding))
  \)
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  redraw
  echo "VimpleNote: Update successful."
  setlocal nomodified
endfunction

function! s:interface.trash_current_note()
  let note = self.get_current_note()
  if empty(note)
    return
  endif

  if len(self.authorization())
    return
  endif

  let url = printf('https://simple-note.appspot.com/api2/data/%s?auth=%s&email=%s', note.key, self.token, http#encodeURI(self.email))
  let res = http#post(url,
  \  http#encodeURI(iconv(json#encode({
  \    'deleted': 1,
  \  }), 'utf-8', &encoding))
  \)
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  echo "VimpleNote: Deleted successful."
  let note['deleted'] = 1
endfunction

function! s:interface.delete_current_note()
  let note = self.get_current_note()
  if empty(note)
    return
  endif

  if len(self.authorization())
    return
  endif

  let url = printf('https://simple-note.appspot.com/api2/data/%s?auth=%s&email=%s', note.key, self.token, http#encodeURI(self.email))
  let res = http#post(url, '', {}, 'DELETE')
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  echo "VimpleNote: Deleted successful."
  let note['deleted'] = 1
endfunction

function! s:interface.set_tags_for_current_note()
  let note = self.get_current_note()
  if empty(note)
    return
  endif

  if len(self.authorization())
    return
  endif

  let note.tags = split(input("Enter tags: ", join(note.tags, ',')), '\s*,\s*')
  let url = printf('https://simple-note.appspot.com/api2/data/%s?auth=%s&email=%s', note.key, self.token, http#encodeURI(self.email))
  let res = http#post(url,
  \  http#encodeURI(iconv(json#encode({
  \    'content': join(getline(1, line('$')), "\n"),
  \    'tags': note.tags,
  \  }), 'utf-8', &encoding))
  \)
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  redraw
  echo "VimpleNote: Tags updated."
endfunction

let s:cmds = {}
let s:cmds["-l"] = { "usage": "list note index in scratch_buffer", "func": s:interface.list_note_index_in_scratch_buffer }
let s:cmds["-d"] = { "usage": "trash current note", "func": s:interface.trash_current_note }
let s:cmds["-D"] = { "usage": "delete current note", "func": s:interface.delete_current_note }
let s:cmds["-u"] = { "usage": "update note from current buffer", "func": s:interface.update_note_from_current_buffer }
let s:cmds["-n"] = { "usage": "create new note from current buffer", "func": s:interface.create_new_note_from_current_buffer }
let s:cmds["-t"] = { "usage": "set tags for current note", "func": s:interface.set_tags_for_current_note }
let s:cmds["-s"] = { "usage": "search notes with tags", "func": s:interface.search_notes_with_tags }

function! vimplenote#VimpleNote(param)
  let args = split(a:param, '\s\+')
  if len(args) > 0 && has_key(s:cmds, args[0])
    call call(get(s:cmds, args[0]).func, args[1:], s:interface)
  else
    echohl ErrorMsg | echomsg "VimpleNote: Unknown argument" | echohl None
    for k in keys(s:cmds)
      echo "VimpleNote " k ":" s:cmds[k].usage
    endfor
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et:
