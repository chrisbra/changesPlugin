" Changes.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.14
" Author:  Christian Brabandt <cb@256bit.org>
" Last Change: Wed, 14 Aug 2013 22:10:39 +0200
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 14 :AutoInstall: ChangesPlugin.vim

" Documentation: "{{{1
" See :h ChangesPlugin.txt

scriptencoding utf-8
let s:i_path = fnamemodify(expand("<sfile>"), ':p:h'). '/changes_icons/'

fu! <sid>GetSID()
    return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_GetSID$')
endfu

let s:sid    = <sid>GetSID()
delf <sid>GetSID "not needed anymore

" Check preconditions
fu! s:Check() "{{{1
    if !exists("s:msg")
	let s:msg=[]
    endif
    if !has("diff")
	call s:StoreMessage("Diff support not available in your Vim version.")
	throw 'changes:abort'
    endif

    if  !has("signs")
	call s:StoreMessage("Sign Support support not available in your Vim.")
	throw 'changes:abort'
    endif

    if !executable("diff") || executable("diff") == -1
	call s:StoreMessage("No diff executable found")
	throw 'changes:abort'
    endif
    if !get(g:, 'changes_respect_SignColumn', 0)
	" Make the Sign column not standout
	hi! link SignColumn Normal
    endif

    " This variable is a prefix for all placed signs.
    " This is needed, to not mess with signs placed by the user
    let s:sign_prefix = 99
    let s:ids={}
    let s:ids["add"]   = hlID("DiffAdd")
    let s:ids["del"]   = hlID("DiffDelete")
    let s:ids["ch"]    = hlID("DiffChange")
    let s:ids["ch2"]   = hlID("DiffText")

    if has("gui_running") && get(g:, 'changes_adjust_linespace', 0)
	" slightly adjust the linespacing, so that the gui signs are drawn 
	" without an ugly horizontal black bar between the icon signs and text
	" signs
	set linespace=-1
    endif
    call s:SetupSignTextHl()
    call s:DefineSigns(0)
endfu

fu! s:DefineSigns(undef) "{{{1
    for key in keys(s:signs)
	if a:undef
	    let s:changes_signs_undefined=1
	    try
		" Try undefining first, so that refining will actually work!
		exe "sil! sign undefine " key
	    catch /^Vim\%((\a\+)\)\=:E155/	" sign does not exist
	    endtry
	endif
	exe "sign define" s:signs[key]
    endfor
endfu

fu! s:CheckLines(arg) "{{{1
    " OLD: not needed any more.
    " a:arg  1: check original buffer
    "        0: check diffed scratch buffer
    let line=1
    while line <= line('$')
	let id=diff_hlID(line,1)
	if  (id == 0)
	    let line+=1
	    continue
	" in the original buffer, there won't be any lines accessible
	" that have been 'marked' deleted, so we need to check scratch
	" buffer for added lines
	elseif (id == s:ids['add']) && !a:arg
	    let s:temp['del']   = s:temp['del'] + [ line ]
	elseif (id == s:ids['add']) && a:arg
	    let b:diffhl['add'] = b:diffhl['add'] + [ line ]
	elseif ((id == s:ids['ch']) || (id == s:ids['ch2']))  && a:arg
	    let b:diffhl['ch']  = b:diffhl['ch'] + [ line ]
	endif
	let line+=1
    endw
endfu

fu! s:UpdateView(...) "{{{1
    " if a:1 is given, force update!
    let force = exists("a:1") && a:1
    if !exists("b:changes_chg_tick")
	let b:changes_chg_tick = 0
    endif
    let b:changes_last_line = get(b:, 'changes_last_line', line('$'))
    if exists("s:ignore")
	if get(s:ignore, bufnr('%'), 0) && !force
	    return
	endif
    endif
    " Only update, if there have been changes to the buffer
    if exists("b:diffhl") &&
	\ line("'[") == line("']") &&
	\ !empty(b:diffhl) &&
	\ index(b:diffhl['add'] + b:diffhl['ch'] + b:diffhl['del'], line("'[")) > -1 &&
	\ b:changes_last_line == line('$')
	" there already is a sign on the current line, so
	" skip an expensive call to create diff (might happen with many
	" rx commands on the same line and triggered TextChanged autocomands)
	" and should make Vim more responsive (at the cost of being a little
	" bit more unprecise.)
	let b:changes_chg_tick = b:changedtick
    endif
    if &buftype==?"help" || &ro
	" Skip Vim help files and readonly files
	return
    endif
	
    if  b:changes_chg_tick != b:changedtick || force
	try
	    call changes#Init()
	    call s:GetDiff(1, '')
	    call s:HighlightTextChanges()
	    let b:changes_chg_tick = b:changedtick
	    let b:changes_last_line = line('$')
	catch
	    call s:StoreMessage(s:msg, v:exception)
	    " Make sure, the message is actually displayed!
	    verbose call changes#WarningMsg()
	    call changes#CleanUp()
	endtry
    endif
endfu

fu! s:PlaceSignDummy(place) "{{{1
    " could be called, without init calling first, so thta s:sign_prefix might
    " not be defined yet. In that case, there can't be a dummy being defined
    " yet!
    if !exists("s:sign_prefix")
	return
    endif
    if a:place
	let b = copy(s:placed_signs[0])
	if !empty(b)
	    " only place signs, if signs have been defined
	    exe "sign place " s:sign_prefix.'0 line='.(line('$')+1). ' name=dummy buffer='. bufnr('')
	endif
    else
	exe "sil sign unplace " s:sign_prefix.'0'
    endif
endfu


fu! s:SetupSignTextHl() "{{{1
    if !hlID('ChangesSignTextAdd') || empty(synIDattr(hlID('ChangesSignTextAdd'), 'fg'))
	" highlighting group does not exist yet
	hi ChangesSignTextAdd ctermbg=46  ctermfg=black guibg=green
    endif
    if !hlID('ChangesSignTextDel') || empty(synIDattr(hlID('ChangesSignTextDel'), 'fg'))
	hi ChangesSignTextDel ctermbg=160 ctermfg=black guibg=red
    endif
    if !hlID('ChangesSignTextCh') || empty(synIDattr(hlID('ChangesSignTextCh'), 'fg'))
	hi ChangesSignTextCh  ctermbg=21  ctermfg=white guibg=blue
    endif
endfu

fu! s:PlaceSigns(dict) "{{{1
    let b = copy(s:placed_signs[1])
    " signs by other plugins
    let changes_signs=[]
    " Give changes a higher prio than adds
    for id in ['add', 'ch', 'del']
	let prev_line = -1 
	for item in a:dict[id]
	    " One special case could occur:
	    " You could delete the last lines. In that case, we couldn't place
	    " here the deletion marks. If this happens, place the deletion
	    " marks on the last line
	    if item > line('$')
		let item=line('$')
	    endif
	    if index(changes_signs, item) > -1
		" There is already a Changes sign placed
		continue
	    endif
	    " There already exists a sign in this line, skip now
	    if index(b, item) > -1
		continue
	    endif
	    let name=id
	    " Make sure, 'dummych' ==? 'ch'
	    " or 'dummydel' ==? 'del'
	    if prev_line+1 == item || s:SignType(s:PrevDictHasKey(item-1)) ==? id
		if id=='del'
		    " don't need to place more deleted signs on those lines,
		    " skip
		    let prev_line = item
		    continue
		else
		    let name='dummy'.id
		endif
	    endif
	    let cmd=printf("sil sign place %d line=%d name=%s buffer=%d",
			\ s:sign_prefix.item, item, name, bufnr(''))
	    exe cmd
	    " remember line number, so that we don't place a second sign
	    " there!
	    call add(changes_signs, item)
	    let prev_line = item
	endfor
    endfor
endfu

fu! s:MySortValues(i1, i2) "{{{1
    return (a:i1+0) == (a:i2+0) ? 0 : (a:i1+0) > (a:i2+0) ? 1 : -1
endfu

fu! s:UnPlaceSigns(force) "{{{1
    if !exists("s:sign_prefix")
	return
    endif
    if a:force
	" only changes sign present, can remove all of them now
	exe "sign unplace * buffer=".bufnr('')
	return
    endif
    if !exists("b:diffhl")
	return
    endif
    call s:UnPlaceSpecificSigns(b:diffhl['add'] + b:diffhl['ch'] + b:diffhl['del'])
endfu

fu! s:Cwd() "{{{1
    return escape(getcwd(), ' ')
endfu

fu! s:StoreMessage(msg, ...) "{{{1
    if !exists("a:1")
	let level=0
    else
	let level=a:1
    endif
    if &vbs>level
	call add(s:msg, a:msg)
    endif
endfu
fu! s:PreviewDiff(file) "{{{1
    try
	if !get(g:, 'changes_diff_preview', 0) || &diff
	    return
	endif
	if getfsize(a:file) <= 0
	    " getfsize() returns -1 on error (e.g. file does not exists!)
	    if bufwinnr(a:file) > 0
		sil! pclose
	    endif
	    return
	endif
	let cur = exists("b:current_line") ? b:current_line : 0
	let _ar=&g:ar
	" Avoid W11 message (:h W11)
	set ar
	try
	    exe printf(':noa keepp noswap sil pedit +/@@\ -%d.*\\n\\zs %s', cur, a:file)
	    let &g:ar=_ar
	    noa wincmd P
	    " execute commands in preview window
	    setl nofoldenable syntax=diff bt=nofile ft=diff
	    sil keepp noa g/^[+-]\{3\}/d_
	catch
	finally
	    " Be sure, to stay in the original window
	    noa wincmd p
	endtry
	if get(g:, 'neocomplcache_enable_auto_close_preview', 0)
	    " Neocomplache closes preview window, GRR!
	    " don't close preview window
	    let g:neocomplcache_enable_auto_close_preview = 0
	endif
    catch
    endtry
endfu
fu! s:MakeDiff_new(file) "{{{1
    " Parse Diff output and place signs
    " Needs unified diff output
    try
	let _pwd = s:ChangeDir()
	unlet! b:current_line
	exe ":sil keepalt noa :w!" s:diff_in_cur
	if !s:vcs || !empty(a:file)
	    let file = !empty(a:file) ? a:file : bufname('')
	    if empty(file)
		throw "changes:abort"
	    endif
	    let cp = (!s:Is('unix') ? 'copy ' : 'cp ')
	    let output = system(cp. shellescape(file). " ". s:diff_in_old)
	    if v:shell_error
		call s:StoreMessage(output[:-2])
		throw "changes:abort"
	    endif
	else
	    if b:vcs_type == 'git'
		let git_rep_p = s:ReturnGitRepPath()
		if !empty(git_rep_p)
		    exe 'lcd' git_rep_p
		endif
	    elseif b:vcs_type == 'cvs'
		" I am not sure, if this is the best way
		" to query CVS. But just to make sure, 
		" we are in the right path and we don't have
		" to consider CVSROOT
		exe 'lcd' fnamemodify(expand('%'), ':p:h')
	    endif
	    let cmd = printf("%s %s%s > %s", (b:vcs_type==?'rcs'?'':
			\ b:vcs_type), s:vcs_cat[b:vcs_type],
			\ shellescape(fnamemodify(resolve(expand('%')), ':.')),
			\ s:diff_in_old)
	    let output = system(cmd)
	    if v:shell_error
		call s:StoreMessage(output[:-2])
		throw "changes:abort"
	    endif
	endif
	let cmd = printf("diff -a -U0 -N %s %s > %s", 
	    \ s:diff_in_old, s:diff_in_cur, s:diff_out)
	let output = system(cmd)
	if v:shell_error >= 2 || v:shell_error < 0
	    " diff returns 2 on errors
	    call s:StoreMessage(output[:-2])
	    throw "changes:abort"
	endif
	if getfsize(s:diff_out) == 0
	    call s:StoreMessage("No differences found!",1)
	    return
	endif
	call s:ParseDiffOutput(s:diff_out)
    finally
	call s:PreviewDiff(s:diff_out)
	if !get(g:, 'changes_debug', 0)
	    for file in [s:diff_in_cur, s:diff_in_old, s:diff_out]
		call delete(file)
	    endfor
	endif
	exe 'lcd' _pwd
    endtry
endfu

fu! s:ChangeDir() "{{{1
    let _pwd = s:Cwd()
    exe "lcd " fnameescape(fnamemodify(expand("%"), ':h'))
    return _pwd
endfu

fu! s:MakeDiff(...) "{{{1
    " Old version, only needed, when GetDiff(3) is called (or argument 1 is non-empty)
    " Get diff for current buffer with original
    let o_pwd = s:ChangeDir()
    let bnr = bufnr('%')
    let ft  = &l:ft
    noa vert new
    set bt=nofile
    let scratchbuf = bufnr('')
    if !s:vcs
	exe ":silent :r " (exists("a:1") && !empty(a:1) ? a:1 : '#')
	let &l:ft=ft
    else
	let vcs=getbufvar(bnr, 'vcs_type')
	try
	    if vcs == 'git'
		let git_rep_p = s:ReturnGitRepPath()
		if !empty(git_rep_p)
		    exe 'lcd' git_rep_p
		endif
	    elseif vcs == 'cvs'
		" I am not sure, if this is the best way
		" to query CVS. But just to make sure, 
		" we are in the right path and we don't have
		" to consider CVSROOT
		exe 'lcd' fnamemodify(expand('#'), ':p:h')
	    endif
	    let output = system((vcs==?'rcs'?'':vcs) . ' '. s:vcs_cat[vcs] .  expand("#") . '>'.  s:diff_out)
	    if v:shell_error
		call s:StoreMessage(output[:-2])
		throw "changes:abort"
	    endif
	    let fsize=getfsize(s:diff_out)
	    if fsize == 0
		call delete(s:diff_out)
		call s:StoreMessage("Couldn't get VCS output, aborting")
		"call s:MoveToPrevWindow()
		exe "noa" bufwinnr(bnr) "wincmd w"
		throw "changes:abort"
	    endif
	    exe ':silent :r' s:diff_out
        catch /^changes: No git Repository found/
	    call s:StoreMessage("Unable to find git Top level repository.")
	    echo v:errmsg
	    exe "noa" bufwinnr(bnr) "wincmd w"
	    throw "changes:abort"
	catch
	    if bufnr('%') != bnr
		"call s:MoveToPrevWindow()
		exe "noa" bufwinnr(bnr) "wincmd w"
	    endif
	    throw "changes:abort"
	finally
	    call delete(s:diff_out)
	endtry
    endif
    0d_
    diffthis
    exe "noa" bufwinnr(bnr) "wincmd w"
    diffthis
    exe "lcd "  o_pwd
    return scratchbuf
endfu

fu! s:ParseDiffOutput(file) "{{{1
    let b:current_line = 1000000 
    for line in filter(readfile(a:file), 'v:val=~''^@@''')
	let submatch = matchlist(line,
	    \ '@@ -\(\d\+\),\?\(\d*\) +\(\d\+\),\?\(\d*\) @@')
	if empty(submatch)
	    " There was probably an error, skip parsing now
	    return
	else
	    let old_line = submatch[1] + 0
	    let old_count = (empty(submatch[2]) ? 1 : submatch[2]) + 0
	    let new_line = submatch[3] + 0
	    let new_count = (empty(submatch[4]) ? 1 : submatch[4]) + 0
	    if b:current_line > (old_line - line('.'))
		let b:current_line = old_line
	    endif
	endif

	" 2 Lines added
	" @@ -4,0 +4,2 @@
	if old_count == 0 && new_count > 0
	    let b:diffhl.add += range(new_line, new_line + new_count - 1)

	" 2 lines deleted:
	" @@ -4,2 +3,0 @@
	elseif old_count > 0 && new_count == 0
	    if new_line == 0
		let new_line = 1
	    endif
	    let b:diffhl.del += range(new_line, new_line + old_count - 1)

	" Lines changed
	" 2 deleted, 2 changed
	" @@ -3,4 +3,2 @@
	elseif old_count >= new_count
	    let b:diffhl.ch += range(new_line, new_line + new_count - 1)
	    if new_line + new_count <= old_line+old_count
		let b:diffhl.del+= range(new_count + new_line, old_line + old_count - 1)
	    endif

	" Lines changed
	" 3 added, 2 changed
	" @@ -4,2 +4,5 @@
	else " old_count < new_count
	    let b:diffhl.ch += range(new_line, new_line + old_count - 1)
	    if new_line + old_count <= new_line+new_count-1
		let b:diffhl.add += range(new_line + old_count, new_line + new_count - 1)
	    endif
	endif
    endfor
endfu

fu! s:ReturnGitRepPath() "{{{1
    " return the top level of the repository path. This is needed, so
    " git show will correctly return the file
    exe 'lcd' fnamemodify(resolve(expand('%')), ':h')
    let git_path = system('git rev-parse --git-dir')
    if !v:shell_error
	" we need the directory right above the .git metatdata directory
	return escape(git_path[:-2].'/..', ' ')
    else
	return ''
    endif
    " OLD....
    let file  =  fnamemodify(expand("#"), ':p')
    let path  =  fnamemodify(file, ':h')
    let dir   =  finddir('.git',path.';')
    if empty(dir)
	throw 'changes: No git Repository found'
    else
	return fnamemodify(dir, ':h')
	let ldir  =  strlen(substitute(dir, '.', 'x', 'g'))-4
	if ldir
	    return file[ldir :]
	else
	    return ''
	endif
    endif
endfu

fu! s:ShowDifferentLines() "{{{1
    if !exists("b:diffhl")
	return
    else
	let list=[]
	let placed={}
	let types={'ch':'*', 'add': '+', 'del': '-'}
	for type in ['ch', 'del', 'add']
	    for line in b:diffhl[type]
		if has_key(placed, line)
		    continue
		endif
		call add(list, {'bufnr': bufnr(''),
		    \ 'lnum': line, 'text': getline(line),
		    \ 'type': types[type]})
		let placed.line=1
	    endfor
	endfor
    endif
    if !empty(list)
	call setloclist(winnr(), list)
	lopen
    endif
endfun

fu! s:PlacedSigns() "{{{1
    if !exists("s:sign_prefix")
	return [[],[]]
    endif
    redir => a| exe "silent sign place buffer=".bufnr('')|redir end
    let b=split(a,"\n")[1:]
    if empty(b)
	return [[],[]]
    endif
    let dict={}
    let mlist=[]
    " Filter from the second item. The first one contains the buffer name:
    " Signs for [NULL]: or  Signs for <buffername>:
    let b=b[1:]
    let c=filter(copy(b), 'v:val =~ "id=".s:sign_prefix')
    for item in c
	let t = split(item)
	let dict.line = split(t[0], '=')[1]
	let dict.id   = split(t[1], '=')[1]
	let dict.type = split(t[2], '=')[1]
	call add(mlist, copy(dict))
    endfor

    "let c=map(c, 'matchstr(v:val, ''line=\zs\d\+\ze'')+0')
    let d=filter(copy(b), 'v:val !~ "id=".s:sign_prefix')
    let d=map(d, 'matchstr(v:val, ''^\s*\w\+=\zs\d\+\ze'')+0')
    return [mlist,d]
endfu

fu! s:GuessVCSSystem() "{{{1
    " Check global config variable
    if exists("g:changes_vcs_system")
	let vcs=matchstr(g:changes_vcs_system, '\c\(git\)\|\(hg\)\|\(bzr\)\|\(svk\)\|\(cvs\)\|\(svn\)'.
		    \ '\|\(subversion\)\|\(mercurial\)\|\(rcs\)\|\(fossil\)\|\(darcs\)')
	if vcs
	    return vcs
	endif
    endif
    let file = fnamemodify(resolve(expand("%")), ':p')
    let path = escape(fnamemodify(file, ':h'), ' ')
    " First try git and hg, they seem to be the most popular ones these days
    if !empty(finddir('.git',path.';'))
	return 'git'
    elseif !empty(finddir('.hg',path.';'))
	return 'hg'
    elseif isdirectory(path . '/CVS')
	return 'cvs'
    elseif isdirectory(path . '/.svn')
	return 'svn'
    elseif !empty(finddir('.bzr',path.';'))
	return 'bzr'
    elseif !empty(findfile('_FOSSIL_', path.';'))
	return 'fossil'
    elseif !empty(finddir('_darcs', path.';'))
	return 'darcs'
    elseif !empty(finddir('RCS', path.';'))
	return 'rcs'
    " Is this correct for svk?
    elseif !empty(finddir('.svn',path.';'))
	return 'svk'
    else
	return ''
    endif
endfu

fu! s:Is(os) "{{{1
    if (a:os == "win")
        return has("win32") || has("win16") || has("win64")
    elseif (a:os == "mac")
        return has("mac") || has("macunix")
    elseif (a:os == "unix")
        return has("unix") || has("macunix")
    endif
endfu

fu! s:RemoveConsecutiveLines(fwd, list) "{{{1
    " only keep the start/end of a bunch of successive lines
    let temp  = -1
    let lines = a:list
    for item in a:fwd ? lines : reverse(lines)
	if  ( a:fwd && temp == item - 1) ||
	\   (!a:fwd && temp == item + 1)
	    call remove(lines, index(lines, item))
	endif
	let temp = item
    endfor
    return lines
endfu

fu! s:GetDiff(arg, bang, ...) "{{{1
    " a:arg == 1 Create signs
    " a:arg == 2 Show changed lines in locationlist
    " a:arg == 3 Stay in diff mode
    
    " If error happened, don't try to get a diff list
    try
	if (exists("s:ignore") && get(s:ignore, bufnr('%'), 0) &&
	    \ empty(a:bang)) || !empty(&l:bt) ||
	    \ line2byte(line('$')) == -1
	    call s:StoreMessage('Buffer is ignored, use ! to force command')
	    return
	elseif !empty(a:bang) && get(s:ignore, bufnr('%'), 0)
	    " remove buffer from ignore list
	    call remove(s:ignore, bufnr('%'))
	endif

	" Save some settings
	let _wsv   = winsaveview()
	" Lazy redraw
	setl lz
	let isfolded = foldclosed('.')
	let scratchbuf = 0

	try
	    if !filereadable(bufname(''))
		call s:StoreMessage("You've opened a new file so viewing changes ".
		    \ "is disabled until the file is saved ")
		return
	    endif

	    " Does not make sense to check an empty buffer
	    if empty(bufname(''))
		call s:StoreMessage("The buffer does not contain a name. Aborted!")
		" don't ignore buffer, it could get a name later...
		return
	    endif

	    let b:diffhl={'add': [], 'del': [], 'ch': []}
	    if a:arg == 3
		let s:temp = {'del': []}
		let curbuf = bufnr('%')
		let _ft = &ft
		let scratchbuf = s:MakeDiff(exists("a:1") ? a:1 : '')
		call s:CheckLines(1)
		exe "noa" bufwinnr(scratchbuf) "wincmd w"
		exe "setl ft=". _ft
		call s:CheckLines(0)
		" Switch to other buffer and check for deleted lines
		exe "noa" bufwinnr(curbuf) "wincmd w"
		let b:diffhl['del'] = s:temp['del']
	    else
		" parse diff output
		call s:MakeDiff_new(exists("a:1") ? a:1 : '')
	    endif
	    call s:SortDiffHl()

	    " Check for empty dict of signs
	    if !exists("b:diffhl") || 
	    \ ((b:diffhl ==? {'add': [], 'del': [], 'ch': []})
	    \ && empty(s:placed_signs[0]))
		" Make sure, diff and previous diff are different,
		" otherwise, we might forget to update the signs
		call s:StoreMessage('No differences found!',1)
		let s:nodiff=1
	    elseif exists("s:changes_signs_undefined") && s:changes_signs_undefined
		call s:PlaceSigns(b:diffhl)
	    else
		let s:diffhl = s:CheckInvalidSigns()
		" diffhl_inv[0] - invalid lines, that need to be removed
		" diffhl_inv[1] - valid lines, that need to be added
		call s:UnPlaceSpecificSigns(s:diffhl[0])
		" Make sure to only place new signs!
		call s:PlaceSigns(s:diffhl[1])
	    endif
	    if a:arg != 3 || s:nodiff
		let b:changes_view_enabled=1
	    endif
	    if a:arg ==# 2
		call s:ShowDifferentLines()
	    endif
	catch /^Vim\%((\a\+)\)\=:E139/	" catch error E139
	    return
	catch /^changes/
	    let b:changes_view_enabled=0
	    let s:ignore[bufnr('%')] = 1
	catch
	    call s:StoreMessage("Error occured: ".v:exception)
	    call s:StoreMessage("Trace: ". v:throwpoint,1)
	finally
	    if scratchbuf && a:arg < 3
		exe "bw" scratchbuf
	    endif
	    if s:vcs && exists("b:changes_view_enabled") &&
			\ b:changes_view_enabled
		" only add info here, when 'verbose' > 1
		call s:StoreMessage("Check against ".
		    \ fnamemodify(expand("%"),':t') . " from " . b:vcs_type, 1)
	    endif
	    " remove dummy sign
	    call s:PlaceSignDummy(0)
	    " redraw (there seems to be some junk left)
	    redr!
	    if isfolded == -1 && foldclosed('.') != -1
		" resetting 'fdm' might fold the cursorline, reopen it
		norm! zv
	    endif
	endtry
    finally
	if exists("_wsv")
	    call winrestview(_wsv)
	endif
	" Make sure, the message is actually displayed!
	verbose call changes#WarningMsg()
	" restore change marks
	call s:SaveRestoreChangeMarks(0)
    endtry
endfu
fu! s:SortDiffHl() "{{{1
    for i in ['add', 'ch', 'del']
	call sort(b:diffhl[i], 's:MySortValues')
	if exists("*uniq")
	    call uniq(b:diffhl[i])
	endif
    endfor
endfu
fu! s:SignType(string) "{{{1
    " returns type but skips dummy type
    return matchstr(a:string, '\(dummy\)\?\zs.*$')
endfu

fu! s:CheckInvalidSigns() "{{{1
    let list=[[],{'add': [], 'del': [], 'ch': []}]
    let ind=0
    for item in s:placed_signs[0]
	if (item.type ==? '[Deleted]')
	    " skip sign prefix '99'
	    call add(list[0], (item.id[2:]+0))
	    continue
	endif
	if index(b:diffhl[s:SignType(item.type)], item.line+0) == -1
	    call add(list[0], item.id[2:])
	    " remove item from the placed sign list, so that we
	    " don't erroneously place a dummy sign later on
	    call remove(s:placed_signs[0], ind)
	else
	    let ind+=1
	endif
    endfor
    for id in ['add', 'ch', 'del']
	for line in b:diffhl[id]
	    if empty(s:PrevDictHasKey(line))
		call add(list[1][id], line)
	    endif
	endfor
    endfor
    return list
endfu

fu! s:PrevDictHasKey(line) "{{{1
    for item in s:placed_signs[0]
	if get(item, 'line', -1) ==? a:line
	    return item.type
	endif
    endfor
    return ''
endfu
fu! s:UnPlaceSpecificSigns(list) "{{{1
    for sign in a:list
	exe "sign unplace ". s:sign_prefix.sign. " buffer=".bufnr('')
    endfor
endfu

fu! s:InitSignDef() "{{{1
    let signs={}
    let s:changes_sign_hi_style = get(s:, 'changes_sign_hi_style', 0)
    let sign_hi = s:changes_sign_hi_style
    if sign_hi == 2
	let add = printf("%s texthl=SignColumn", "\<Char-0xa0>")
	let del = printf("%s texthl=SignColumn", "\<Char-0xa0>")
	let ch  = printf("%s texthl=SignColumn", "\<Char-0xa0>")
    else
	let add = printf("%s texthl=%s %s",
		\ (get(g:, 'changes_sign_text_utf8', 0) ? '⨁' : '+'), 
		\ (sign_hi<2 ? "ChangesSignTextAdd" : "SignColumn"),
		\ (has("gui_running") ? 'icon='.s:i_path.'add1.bmp' : ''))
	let del = printf("%s texthl=%s %s",
		\ (get(g:, 'changes_sign_text_utf8', 0) ? '➖' : '-'),
		\ (sign_hi<2 ? "ChangesSignTextDel" : "SignColumn"),
		\ (has("gui_running") ? 'icon='.s:i_path.'delete1.bmp' : ''))
	let ch  = printf("%s texthl=%s  %s",
		\ (get(g:, 'changes_sign_text_utf8', 0) ? '★' : '*'),
		\ (sign_hi<2 ? "ChangesSignTextCh" : "SignColumn"),
		\ (has("gui_running") ? 'icon='.s:i_path.'warning1.bmp' : ''))
    endif

    let signs["add"] = "add text=".add
    let signs["ch"]  = "ch  text=".ch
    let signs["del"] = "del text=".del

    " Add some more dummy signs
    let signs["dummy"]    = "dummy text=\<Char-0xa0>\<Char-0xa0> texthl=SignColumn"
    let signs["dummyadd"] = "dummyadd text=\<Char-0xa0>\<Char-0xa0> texthl=".
		\ (sign_hi<2 ? "ChangesSignTextAdd" : "SignColumn")
    let signs["dummych"]  = "dummych text=\<Char-0xa0>\<Char-0xa0> texthl=".
		\ (sign_hi<2 ? "ChangesSignTextCh" : "SignColumn")

    if sign_hi > 0
	let signs['add'] .= ' linehl=DiffAdd'
	let signs['ch'] .= ' linehl=DiffChange'
	let signs['del'] .= ' linehl=DiffDelete'
	let signs['dummyadd'] .= ' linehl=DiffAdd'
	let signs['dummych'] .= ' linehl=DiffChange'
    endif
    return signs
endfu
fu! s:SaveRestoreChangeMarks(save) "{{{1
    if a:save
	let s:_change_mark = [getpos("'["), getpos("']")]
    else
	for i in [0,1]
	    call setpos("'".(i?']':'['), s:_change_mark[i])
	endfor
    endif
endfu
fu! s:HighlightTextChanges() "{{{1
    " use the '[ and '] marks (if they are valid)
    " and highlight changes
    let seq_last=undotree()['seq_last']
    let seq_cur =undotree()['seq_cur']
    if seq_last > seq_cur && exists("b:changes_linehi_diff_match") &&
		\ len(b:changes_linehi_diff_match) > 0
	" change was undo
	" remove last highlighting (this is just a guess!)
	for [change, val] in items(b:changes_linehi_diff_match)
	    if change > seq_cur
		sil call matchdelete(val)
		unlet! b:changes_linehi_diff_match[change]
	    endif
	endfor
	return
    endif
    if get(g:, 'changes_linehi_diff', 0) &&
    \  (getpos("'[")[1] !=? 1 ||
    \  getpos("']")[1] !=? line('$')) &&
    \  getpos("']") !=? getpos("'[")
    " ignore those marks, if they are
    " - not set (e.g. they are [0,0,0,0]
    " - or '[ and '] are the same (happens when deleting lines)
    " - or they do not match the complete buffer
	call s:AddMatches(
	\ s:GenerateHiPattern(getpos("'[")[1:2], getpos("']")[1:2]))
    endif
endfu
fu! s:GenerateHiPattern(startl, endl) "{{{1
    " startl - Start Position [line, col]
    " endl   - End Position   [line, col]
    " Easy way: match within a line
    if a:startl[0] == a:endl[0]
	return '\%'.a:startl[0]. 'l\%>'.(a:startl[1]-1).'c.*\%<'.a:endl[1].'c'
    else
	" Need to generate concat 3 patterns:
	"  1) from startline, startcolumn till end of line
	"  2) all lines between startline and end line
	"  3) from start of endline until end column
	"
	" example: Start at line 1 col. 6 until line 3 column 12:
	" \%(\%1l\%>6v.*\)\|\(\%>1l\%<3l.*\)\|\(\%3l.*\%<12v\)
    return  '\%(\%'.  a:startl[0]. 'l\%>'. (a:startl[1]-1). 'c.*\)\|'.
	    \	'\%(\%>'. a:startl[0]. 'l\%<'. a:endl[0]. 'l.*\)\|'.
	    \   '\%(\%'.  a:endl[0]. 'l.*\%<'. a:endl[1]. 'c\)'
    endif
endfu 
fu! s:AddMatches(pattern) "{{{1
    if  !empty(a:pattern)
	if !exists("b:changes_linehi_diff_match")
		let b:changes_linehi_diff_match = {}
	endif
	let b:changes_linehi_diff_match[changenr()] = matchadd('CursorLine', a:pattern)
    endif
endfu
fu! changes#GetStats() "{{{1
    return [len(get(get(b:, 'diffhl', []), 'add', [])),
	    \ len(get(get(b:, 'diffhl', []), 'ch', [])),
	    \ len(get(get(b:, 'diffhl', []), 'del', []))]
endfu

fu! changes#WarningMsg() "{{{1
    if !&vbs
	" Set verbose to 1 to have messages displayed!
	return
    endif
    if !empty(s:msg)
	redraw!
	let msg=["Changes.vim: " . s:msg[0]] + s:msg[1:]
	echohl WarningMsg
	for mess in msg
	    echomsg mess
	endfor

	echohl Normal
	let v:errmsg=msg[0]
	let s:msg = []
    endif
endfu

fu! changes#Output() "{{{1
    let add = '+'
    let ch  = '*'
    let del = '-'
    let sign_def = s:signs
    if !empty(sign_def)
	let add = matchstr(sign_def['add'], 'text=\zs..')
	let ch  = matchstr(sign_def['ch'], 'text=\zs..')
	let del = matchstr(sign_def['del'], 'text=\zs..')
    endif
    echohl Title
    echo "Differences will be highlighted like this:"
    echohl Normal
    echo "========================================="
    echohl ChangesSignTextAdd
    echo add. " Added Lines"
    echohl ChangesSignTextDel
    echo del. " Deleted Lines"
    echohl ChangesSignTextCh
    echo ch. " Changed Lines"
    echohl Normal
endfu

fu! changes#Init() "{{{1
    " Message queue, that will be displayed.
    let s:msg      = []
    " save change marks
    call s:SaveRestoreChangeMarks(1)
    " Ignore buffer
    let s:ignore   = {}
    let s:changes_signs_undefined=0
    let s:autocmd  = get(g:, 'changes_autocmd', 1)
    " Check against a file in a vcs system
    let s:vcs      = get(g:, 'changes_vcs_check', 0)
    if !exists("b:vcs_type")
	let b:vcs_type = (exists("g:changes_vcs_system")? g:changes_vcs_system : s:GuessVCSSystem())
    endif
    if s:vcs && empty(b:vcs_type)
	" disable VCS checking...
	let s:vcs=0
    endif
    if !exists("s:vcs_cat")
	let s:vcs_cat  = {'git': 'show HEAD:', 
			 \'bzr': 'cat ', 
			 \'cvs': '-q update -p ',
			 \'darcs': '--show-contents ',
			 \'fossil': 'finfo -p ',
			 \'rcs': 'co -p ',
			 \'svn': 'cat ',
			 \'svk': 'cat ',
			 \'hg': 'cat '}

	" Define aliases...
	let s:vcs_cat.mercurial  = s:vcs_cat.hg
	let s:vcs_cat.subversion = s:vcs_cat.svn
    endif
"    if !exists("s:vcs_diff")
"	let s:vcs_diff  = {'git': 'diff -a -U0 --no-ext-diff -- ', 
"			 \'bzr': 'diff --using diff --diff-options=-U0 -- ', 
"			 \'cvs': '-q diff -U0 -- ',
"			 \'darcs': 'diff --no-pause-for-gui --diff-command="diff -U0 %1 %2" -- ',
"			 \'fossil': 'fossil diff --unified -- ',
"			 \'rcs': 'rcsdiff -U0 ',
"			 \'svn': 'diff -x -u --ignore-eol-style -- ',
"			 \'svk': 'diff -x -u --ignore-eol-style -- ',
"			 \'hg': 'diff -U0 --nodates -- '}
"	" Define aliases...
"	let s:vcs_diff.subversion = s:vcs_diff.svn
"	let s:vcs_diff.mercurial  = s:vcs_diff.hg
"    endif

    " Settings for Version Control
    if s:vcs && !empty(b:vcs_type)
	if get(s:vcs_cat, b:vcs_type, 'NONE') == 'NONE'
	    call s:StoreMessage("Don't know VCS " . b:vcs_type)
	    call s:StoreMessage("VCS check will be disabled for now.")
	    let s:vcs=0
	    " Probably file not in a repository/working dir
	    throw 'changes:NoVCS'
	endif
	if !executable(b:vcs_type)
	    call s:StoreMessage("Guessing VCS: ". b:vcs_type)
	    call s:StoreMessage("Executable " . b:vcs_type . " not found! Aborting.")
	    call s:StoreMessage("You might want to set the g:changes_vcs_system variable to override!")
	    throw "changes:abort"
	endif
    endif
    if !exists("s:diff_out")
	let s:diff_out    = tempname()
	let s:diff_in_cur = s:diff_out.'cur'
	let s:diff_in_old = s:diff_out.'old'
    endif
    let s:nodiff=0
    let s:old_signs = get(s:, 'signs', {})
    let s:signs=s:InitSignDef()

    " Only check the first time this file is loaded
    " It should not be neccessary to check every time
    if !exists("s:precheck")
	try
	    call s:Check()
	catch
	    call s:StoreMessage("changes plugin will not be working!")
	    " Rethrow exception
	    throw changes:abort
	endtry
	let s:precheck=1
    endif
    let s:placed_signs = s:PlacedSigns()
    if !empty(s:placed_signs[1])
	" when there are signs from other plugins, don't need dummy sign
	call s:PlaceSignDummy(1)
    endif
    " Delete previously placed signs
    " not necessary, if we are only selectively update signs
    " call s:UnPlaceSigns(0)
    if s:old_signs !=? s:signs
	" Sign definition changed, redefine them
	call s:DefineSigns(1)
    endif
    call changes#AuCmd(s:autocmd)
endfu

fu! changes#EnableChanges(arg, bang, ...) "{{{1
    if exists("s:ignore") && get(s:ignore, bufnr('%'), 0)
	call remove(s:ignore, bufnr('%'))
    endif
    try
	call changes#Init()
	let arg = exists("a:1") ? a:1 : ''
	call s:GetDiff(a:arg, a:bang, arg)
    catch
	call changes#CleanUp()
    endtry
endfu

fu! changes#CleanUp() "{{{1
    " only delete signs, that have been set by this plugin
    call s:UnPlaceSigns(1)
    let s:ignore[bufnr('%')] = 1
    for key in keys(s:signs)
	exe "sil! sign undefine " key
    endfor
    if s:autocmd
	call changes#AuCmd(0)
    endif
    let b:changes_view_enabled = 0
    if exists("b:changes_linehi_diff_match")
	for val in values(b:changes_linehi_diff_match)
	    call matchdelete(val)
	endfor
    endif
    unlet! b:diffhl s:signs s:old_signs b:changes_linehi_diff_match
endfu
fu! changes#AuCmd(arg) "{{{1
    if a:arg
	if !exists("#Changes")
	    augroup Changes
		autocmd!
		au TextChanged,InsertLeave,FilterReadPost * :call s:UpdateView()
		au FocusGained,BufWinEnter * :call s:UpdateView(1)
		" make sure, hightlighting groups are not cleared
		au GUIEnter * :try|call s:Check() |catch|endtry
	    augroup END
	endif
    else
	augroup Changes
	    autocmd!
	augroup END
	augroup! Changes
    endif
endfu
fu! changes#TCV() "{{{1
    if  exists("b:changes_view_enabled") && b:changes_view_enabled
	call s:UnPlaceSigns(1)
        let b:changes_view_enabled = 0
        echo "Hiding changes since last save"
    else
	try
	    call changes#Init()
	    call s:GetDiff(1, '')
	    let b:changes_view_enabled = 1
	    echo "Showing changes since last save"
	catch
	    " Make sure, the message is actually displayed!
	    verbose call changes#WarningMsg()
	    call changes#CleanUp()
	endtry
    endif
endfunction

fu! changes#MoveToNextChange(fwd, cnt) "{{{1
    " Make sure, the hunks are up to date
    let _fen = &fen
    set nofen
    call s:UpdateView()
    let &fen = _fen

    let cur = line('.')
    let dict = get(b:, "diffhl", {})
    let lines = get(dict, "add", []) +
	    \   get(dict, "del", []) +
	    \   get(dict, "ch",  [])
    let lines = sort(lines, 's:MySortValues')
    if exists('*uniq')
	" remove duplicates
	let lines = uniq(lines)
    endif
    if mode() =~? '[vs]' && index(lines, cur) == -1
	" in visual mode and not within a hunk!
	return "\<esc>"
    endif

    let suffix = '0' " move to start of hunk
    let cnt = a:cnt-1

    " only keep the start/end of a bunch of successive lines
    let lines = s:RemoveConsecutiveLines(1, copy(lines)) +
	      \ s:RemoveConsecutiveLines(0, copy(lines))
    " sort again...
    let lines = sort(lines, 's:MySortValues')

    if empty(lines)
	echomsg   "There are no ". (a:fwd ? "next" : "previous").
		\ " differences!"
	return "\<esc>"
    elseif (a:fwd && max(lines) <= cur) ||
	\ (!a:fwd && min(lines) >= cur)
	echomsg   "There are no more ". (a:fwd ? "next" : "previous").
		\ " differences!"
	return "\<esc>"
    endif
    if a:fwd
	call filter(lines, 'v:val > cur')
	if empty(lines)
	    return "\<esc>"
	endif
    else
	call filter(lines, 'v:val < cur')
	if empty(lines)
	    return "\<esc>"
	else
	    call reverse(lines)
	endif
    endif
    if cnt > len(lines)
	let cnt=length(lines)
    endif

    " Cancel the user given count
    " otherwise the count would be multiplied with
    " the given line number
    let prefix=(cnt > 0 ? "\<esc>" : "")
    return prefix.lines[cnt]. "G".suffix
endfu

fu! changes#CurrentHunk() "{{{1
    if changes#MoveToNextChange(0,1) == "\<Esc>"
	" outside of a hunk
	return "\<Esc>"
    else
	return "[ho]h$"
    endif
endfu
fu! changes#FoldDifferences(enable) "{{{1
    if empty(a:enable) && &fde!=?'index(g:lines,v:lnum)>-1?0:1'
	let b:chg_folds = {'fen': &fen, 'fdm': &fdm, 'fde': &fde}
	let g:lines=sort(get(get(b:, 'diffhl', []), 'add', []) +
		\ get(get(b:, 'diffhl', []), 'ch' , []) +
		\ get(get(b:, 'diffhl', []), 'del', []),
		\ 's:MySortValues')
	if exists('*uniq')
	    let lines=uniq(g:lines)
	endif
	setl fen fdm=expr fde=index(g:lines,v:lnum)>-1?0:1
    else
	for items in items(get(b:, 'chg_folds', {}))
	    exe "let &".items[0]."=".string(items[1])
	endfor
    endif
endfu

fu! changes#ToggleHiStyle() "{{{1
    let s:changes_sign_hi_style += 1
    if s:changes_sign_hi_style > 2
	let s:changes_sign_hi_style = 0
    endif
    try
	call changes#Init()
	call s:GetDiff(1, '')
    catch
	" Make sure, the message is actually displayed!
	verbose call changes#WarningMsg()
	call changes#CleanUp()
    endtry
endfu
" Modeline "{{{1
" vi:fdm=marker fdl=0
