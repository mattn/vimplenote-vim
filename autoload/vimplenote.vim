"=============================================================================
" vimplenote.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 01-Nov-2011.

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

function! s:GetNoteToCurrentBuffer()
  call s:interface.display_note_in_scratch_buffer()
endfunction

function! s:interface.list_note_index_in_scratch_buffer() dict
  if len(self.authorization())
    return
  endif

  let datas = {
  \ "data": [],
  \}
  let mark = ''
  while 1
    let url = printf('https://simple-note.appspot.com/api2/index?auth=%s&email=%s&length=%s&mark=%s', self.token, http#encodeURI(self.email), 20, mark)
    let res = http#get(url)
    if res.header[0] != 'HTTP/1.1 200 OK'
      echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
      return
    endif
    let obj = json#decode(iconv(res.content, 'utf-8', &encoding))
    let datas.data = extend(datas.data, obj.data)
    if !has_key(obj, 'mark')
      break
    endif
    let mark = obj.mark
  endwhile

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
      let data = json#decode(iconv(res.content, 'utf-8', &encoding))
      let lines = split(data.content, "\n")
      call add(self.notes, {
      \  "title": len(lines) > 0 ? lines[0] : '',
      \  "tags": note.tags,
      \  "key": note.key,
      \  "modifydate": note.modifydate,
      \})
    endif
  endfor

  call self.open_scratch_buffer("==VimpleNote==")
  silent %d _
  call setline(1, map(copy(self.notes), 'printf("%s [%s]", strftime("%Y/%m/%d %H:%M:%S", v:val.modifydate), matchstr(v:val.title, "^.*\\%<60c"))'))
  nnoremap <buffer> <cr> :call <SID>GetNoteToCurrentBuffer()<cr>
  setlocal nomodified
endfunction

function! s:UpdateNoteFromCurrentBuffer()
  call s:interface.update_note_from_current_buffer()
endfunction

function! s:interface.display_note_in_scratch_buffer() dict
  if len(self.authorization())
    return
  endif

  let note = self.notes[line('.')-1]
  let url = printf('https://simple-note.appspot.com/api2/data/%s?auth=%s&email=%s', note.key, self.token, http#encodeURI(self.email))
  let res = http#get(url)
  if res.header[0] != 'HTTP/1.1 200 OK'
    echohl ErrorMsg | echomsg "VimpleNote: " res.header[0] | echohl None
    return
  endif
  let content = json#decode(iconv(res.content, 'utf-8', &encoding)).content

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
  let note = json#decode(iconv(res.content, 'utf-8', &encoding))
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
let s:cmds["-l"] = s:interface.list_note_index_in_scratch_buffer
let s:cmds["-d"] = s:interface.trash_current_note
let s:cmds["-D"] = s:interface.delete_current_note
let s:cmds["-u"] = s:interface.update_note_from_current_buffer
let s:cmds["-n"] = s:interface.create_new_note_from_current_buffer
let s:cmds["-t"] = s:interface.set_tags_for_current_note

function! vimplenote#VimpleNote(param)
  if has_key(s:cmds, a:param)
    call call(get(s:cmds, a:param), a:000, s:interface)
  else
    echohl ErrorMsg | echomsg "VimpleNote: Unknown argument" | echohl None
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et:
