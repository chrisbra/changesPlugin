" Changes.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.14
" Authors:  Christian Brabandt <cb@256bit.org>
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
    " Check for the existence of unsilent
    let s:echo_cmd='unsilent echo'

    if !has("diff")
	call add(s:msg,"Diff support not available in your Vim version.")
	throw 'changes:abort'
    endif

    if  !has("signs")
	call add(s:msg,"Sign Support support not available in your Vim.")
	throw 'changes:abort'
    endif

    if !executable("diff") || executable("diff") == -1
	call add(s:msg,"No diff executable found")
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

    if has("gui_running")
	" slightly adjust the linespacing, so that the gui signs are drawn 
	" without an ugly horizontal black bar between the icon signs and text
	" signs
	set linespace=-1
    endif
    unlet! s:sign_definition
    call s:SetupSignTextHl()
    call s:DefineSigns()
endfu

fu! s:DefineSigns() "{{{1
    for key in keys(s:signs)
	try
	    exe "sign define" s:signs[key]
	catch /^Vim\%((\a\+)\)\=:E155/	" sign does not exist
	endtry
    endfor
endfu

fu! s:CheckLines(arg) "{{{1
    " OLD: not needed any more.
    " a:arg  1: check original buffer
    "        0: check diffed scratch buffer
    let line=1
    " This should not be necessary, since b:diffhl for the scratch buffer
    " should never be accessed. But just to be sure, we define it here
"    if (!a:arg) && !exists("b:diffhl")
"	let b:diffhl = {'del': []}
"    endif
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
    " Only update, if there have been changes to the buffer
    if  b:changes_chg_tick != b:changedtick || force
	call changes#Init()
	call s:GetDiff(1, '')
	let b:changes_chg_tick = b:changedtick
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
	if empty(s:DefinedSignsNotExists())
	    call s:DefineSigns()
	endif
	let b = copy(s:placed_signs[0])
	if !empty(b)
	    " only place signs, if signs have been defined
	    exe "sign place " s:sign_prefix.'0 line='.(line('$')+1). ' name=dummy buffer='. bufnr('')
	endif
    else
	exe "sign unplace " s:sign_prefix.'0'
    endif
endfu

fu! s:DefinedSignsNotExists() "{{{1
    if !exists("s:sign_definition")
	redir => a|exe "sil sign list"|redir end
	let s:sign_definition = split(a, "\n")
    endif
    let s:sign_definition = filter(s:sign_definition, 'v:val !~# "dummy"')
    let pat = '^sign \(add\|del\|ch\)'
    let b = filter(copy(s:sign_definition), 'v:val =~ pat')
    let b = map(b, 'substitute(v:val, ''^\w\+\s\+'', "", "")')
    return b
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
    if empty(s:DefinedSignsNotExists())
	call s:DefineSigns()
    endif
    let b = copy(s:placed_signs[1])
    " signs by other plugins
    let b = map(b, 'matchstr(v:val, ''line=\zs\d\+'')+0')
    let changes_signs=[]
    " Give changes a higher prio than adds
    for id in ['ch', 'del', 'add']
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
	    exe "sil sign place " s:sign_prefix . item . " line=" . item .
		\ " name=" . (prev_line+1 == item ? "dummy".id : id) . " buffer=" . bufnr('')
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
    for sign in b:diffhl['add'] + b:diffhl['ch'] + b:diffhl['del']
	exe "sign unplace ". s:sign_prefix.sign. " buffer=".bufnr('')
    endfor
endfu

fu! s:Cwd() "{{{1
    return escape(getcwd(), ' ')
endfu

fu! s:PreviewDiff(file) "{{{1
    try
	if !exists('g:changes_did_startup') ||
	    \  !get(g:, 'changes_diff_preview', 0) || &diff
	    return
	endif
	let cnt = readfile(a:file)
	let fname=fnamemodify(expand('%'), ':p:.')
	if len(cnt) > 2
	    let cnt[0] = substitute(cnt[0], s:diff_in_old, fname, '')
	    let cnt[1] = substitute(cnt[1], s:diff_in_cur, fname." (cur)", '')
	    call writefile(cnt, a:file)
	endif

	let bufnr = bufnr('')
	let cur = exists("b:current_line") ? b:current_line : 0
	if cur
	    exe printf(':noa sil! pedit +/@@\ -%d.*\\n\\zs %s', cur, a:file)
	    call setbufvar(a:file, "&ft", "diff")
	    call setbufvar(a:file, '&bt', 'nofile')
	    exe "noa" bufwinnr(bufnr)."wincmd w"
	    if get(g:, 'neocomplcache_enable_auto_close_preview', 0)
		" Neocomplache closes preview window, GRR!
		" don't close preview window
		let g:neocomplcache_enable_auto_close_preview = 0
	    endif
	else
	    sil! pclose
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
		call add(s:msg, output[:-2])
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
		call add(s:msg, output[:-2])
		throw "changes:abort"
	    endif
	endif
	let cmd = printf("diff -a -U0 -N %s %s > %s", 
	    \ s:diff_in_old, s:diff_in_cur, s:diff_out)
	let output = system(cmd)
	if v:shell_error >= 2 || v:shell_error < 0
	    " diff returns 2 on errors
	    call add(s:msg, output[:-2])
	    throw "changes:abort"
	endif
	if getfsize(s:diff_out) == 0
	    call add(s:msg,"No differences found!")
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

fu! s:ChangeDir()
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
		call add(s:msg, output[:-2])
		throw "changes:abort"
	    endif
	    let fsize=getfsize(s:diff_out)
	    if fsize == 0
		call delete(s:diff_out)
		call add(s:msg,"Couldn't get VCS output, aborting")
		"call s:MoveToPrevWindow()
		exe "noa" bufwinnr(bnr) "wincmd w"
		throw "changes:abort"
	    endif
	    exe ':silent :r' s:diff_out
        catch /^changes: No git Repository found/
	    call add(s:msg,"Unable to find git Top level repository.")
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

	" Line added
	if old_count == 0 && new_count > 0
	    let b:diffhl.add += range(new_line, new_line + new_count - 1)
	elseif old_count > 0 && new_count == 0
	    if new_line == 0
		let new_line = 1
	    endif
	    let b:diffhl.del += range(new_line, new_line + old_count - 1)
	" Line changed
	elseif old_count >= new_count
	    let b:diffhl.ch += range(new_line, new_line + new_count - 1)
	else
	    let b:diffhl.ch += range(new_line, new_line + old_count - 1)
	    let b:diffhl.add += range(new_line, new_line + new_count - 1)
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
    " Filter from the second item. The first one contains the buffer name:
    " Signs for [NULL]: or  Signs for <buffername>:
    let b=b[1:]
    let c=filter(copy(b), 'v:val =~ "id=".s:sign_prefix')
    let d=filter(copy(b), 'v:val !~ "id=".s:sign_prefix')
    return [c,d]
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

fu! s:CheckDeletedLines() "{{{1
    " If there are consecutive deleted lines,
    " we keep only the first of the deleted lines
    let i=0
    for item in b:diffhl['del']
	if item > line('$')
	    let b:diffhl['del'][i]=line('$')
	    return
	endif
	if i==0
	    let i+=1
	    let last_line = item
	    continue
	endif
	if last_line ==? (item-1)
	    call remove(b:diffhl['del'], i)
	    let last_line=item
	    continue
	endif
	let last_line=item
	let i+=1
    endfor
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
	    call add(s:msg, 'Buffer is ignored, use ! to force command')
	    " ignore error messages
	    if get(s:ignore, bufnr('%'), 0)
		call remove(s:ignore, bufnr('%'))
	    endif
	    return
	endif

	" Save some settings
	let _wsv   = winsaveview()
	" Lazy redraw
	setl lz
	let isfolded = foldclosed('.')
	let scratchbuf = 0

	try
	    if !filereadable(bufname(''))
		call add(s:msg,"You've opened a new file so viewing changes ".
		    \ "is disabled until the file is saved ")
		return
	    endif

	    " Does not make sense to check an empty buffer
	    if empty(bufname(''))
		call add(s:msg,"The buffer does not contain a name. Aborted!")
		" don't ignore buffer, it could get a name later...
		" let s:ignore[bufnr('%')] = 1
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

	    " Check for empty dict of signs
	    if (!exists("b:diffhl") || 
	    \ b:diffhl ==? {'add': [], 'del': [], 'ch': []})
		call add(s:msg, 'No differences found!')
		let s:nodiff=1
	    else
		call s:PlaceSigns(b:diffhl)
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
	finally
	    if scratchbuf && a:arg < 3
		exe "bw" scratchbuf
	    endif
	    if s:vcs && exists("b:changes_view_enabled") &&
			\ b:changes_view_enabled
		call add(s:msg,"Check against " .
		    \ fnamemodify(expand("%"),':t') . " from " . b:vcs_type)
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
	" make sure on next call, s:sign-definition will be recreated by
	" DefinedSignsNotExists()
	unlet! s:sign_definition
	call changes#WarningMsg()
    endtry
endfu

fu! s:CheckDifferenceDefinition(a) "{{{1
    return   sort(split(a:a[0])) !=? sort(split(s:signs.add))
	\ || sort(split(a:a[1])) !=? sort(split(s:signs.ch))
	\ || sort(split(a:a[2])) !=? sort(split(s:signs.del))
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
	" s:echo_cmd might not yet exist
	if !exists("s:echo_cmd")
	    let s:echo_cmd = 'echo'
	endif
	for mess in msg
	    exe s:echo_cmd "mess"
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
    let sign_def = s:DefinedSignsNotExists()
    if !empty(sign_def)
	let add = matchstr(sign_def[0], 'text=\zs..')
	let ch  = matchstr(sign_def[1], 'text=\zs..')
	let del = matchstr(sign_def[2], 'text=\zs..')
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
    " Ignore buffer
    let s:ignore   = {}
    let s:hl_lines = get(g:, 'changes_hl_lines', 0)
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
	    call add(s:msg,"Don't know VCS " . b:vcs_type)
	    call add(s:msg,"VCS check will be disabled for now.")
	    let s:vcs=0
	    " Probably file not in a repository/working dir
	    throw 'changes:NoVCS'
	endif
	if !executable(b:vcs_type)
	    call add(s:msg,'Guessing VCS: '. b:vcs_type)
	    call add(s:msg,"Executable " . b:vcs_type . " not found! Aborting.")
	    call add(s:msg,'You might want to set the g:changes_vcs_system variable to override!')
	    throw "changes:abort"
	endif
    endif
    if !exists("s:diff_out")
	let s:diff_out    = tempname()
	let s:diff_in_cur = s:diff_out.'cur'
	let s:diff_in_old = s:diff_out.'old'
    endif
    let s:nodiff=0

    let s:signs={}
    let add = printf("%s", get(g:, 'changes_sign_text_utf8', 0) ? '⨁' : '+')
    let del = printf("%s", get(g:, 'changes_sign_text_utf8', 0) ? '➖' : '-')
    let ch  = printf("%s", get(g:, 'changes_sign_text_utf8', 0) ? '★' : '*')

    let s:signs["add"] = "add text=".add."  texthl=ChangesSignTextAdd " .
		\( (s:hl_lines) ? " linehl=DiffAdd" : "") . 
		\ (has("gui_running") ? 'icon='.s:i_path.'add1.bmp' : '')
    let s:signs["del"] = "del text=".del."  texthl=ChangesSignTextDel " .
		\( (s:hl_lines) ? " linehl=DiffDelete" : "") .
		\ (has("gui_running") ? 'icon='.s:i_path.'delete1.bmp' : '')
    let s:signs["ch"]  = "ch text=\<Char-0xa0>".ch. "  texthl=ChangesSignTextCh "  .
		\ ( (s:hl_lines) ? " linehl=DiffChange" : "") .
		\ (has("gui_running") ? 'icon='.s:i_path.'warning1.bmp' : '')
    " Add some more dummy signs
    let s:signs["dummy"]    = "dummy text=\<Char-0xa0>\<Char-0xa0> texthl=SignColumn "
    let s:signs["dummyadd"] = "dummyadd text=\<Char-0xa0>\<Char-0xa0> texthl=ChangesSignTextAdd " . ( (s:hl_lines) ? " linehl=DiffAdd" : "")
    let s:signs["dummydel"] = "dummydel text=\<Char-0xa0>\<Char-0xa0> texthl=ChangesSignTextDel " . ( (s:hl_lines) ? " linehl=DiffDelete" : "")
    let s:signs["dummych"]  = "dummych text=\<Char-0xa0>\<Char-0xa0> texthl=ChangesSignTextCh "  . ( (s:hl_lines) ? " linehl=DiffChange" : "")

    " Only check the first time this file is loaded
    " It should not be neccessary to check every time
    if !exists("s:precheck")
	try
	    call s:Check()
	catch
	    call add(s:msg,"changes plugin will not be working!")
	    " Rethrow exception
	    throw v:exception
	endtry
	let s:precheck=1
    endif
    let s:placed_signs = s:PlacedSigns()
    call s:PlaceSignDummy(1)
    " Delete previously placed signs
    call s:UnPlaceSigns(0)
    if exists("s:sign_definition")
	let def = sort(s:DefinedSignsNotExists())
	if len(def) < 3 || s:CheckDifferenceDefinition(def)
	    " Sign definition changed, redefine them
	    call s:DefineSigns()
	endif
    else
	call s:DefineSigns()
    endif
    call changes#AuCmd(s:autocmd)
endfu

fu! changes#EnableChanges(arg, bang, ...) "{{{1
    if exists("s:ignore") && get(s:ignore, bufnr('%'), 0)
	call remove(s:ignore, bufnr('%'))
    endif
    call changes#Init()
    if exists("a:1")
	call s:GetDiff(a:arg, a:bang, a:1)
    else
	call s:GetDiff(a:arg, a:bang)
    endif
endfu

fu! changes#CleanUp() "{{{1
    " only delete signs, that have been set by this plugin
    call s:UnPlaceSigns(1)
    let s:ignore[bufnr('%')] = 1
    if !exists("s:signs") || !exists("s:autocmd")
	return
    endif
    for key in keys(s:signs)
	exe "sil! sign undefine " key
    endfor
    if s:autocmd
	call changes#AuCmd(0)
    endif
    let b:changes_view_enabled = 0
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
	if exists("b:ofdc")
	    let &fdc=b:ofdc
	endif
        let b:changes_view_enabled = 0
        echo "Hiding changes since last save"
    else
	call changes#Init()
	call s:GetDiff(1, '')
        let b:changes_view_enabled = 1
        echo "Showing changes since last save"
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
    let cnt = a:cnt-1

    " only keep the start/end of a bunch of successive lines
    let lines = s:RemoveConsecutiveLines(1, copy(lines)) +
	      \ s:RemoveConsecutiveLines(0, copy(lines))

    if !exists("b:diffhl") || empty(lines)
	echomsg "There are no ". (a:fwd ? "next" : "previous"). " differences!"
	return "\<esc>"
    elseif (a:fwd && max(lines) <= cur) ||
	\ (!a:fwd && min(lines) >= cur)
	echomsg "There are no more ". (a:fwd ? "next" : "previous"). " differences!"
	return "\<esc>"
    endif
    if a:fwd
	call filter(lines, 'v:val > cur')
	if empty(lines)
	    return "\<esc>"
	else
	    call sort(lines)
	endif
    else
	call filter(lines, 'v:val < cur')
	if empty(lines)
	    return "\<esc>"
	else
	    call reverse(sort(lines))
	endif
    endif
    if cnt > len(lines)
	let cnt=length(lines)
    endif

    if cnt > 0
	" Cancel the user given count
	" otherwise the count would be multiplied with
	" the given line number
	let prefix="\<esc>"
    else
	let prefix=""
    endif
    return prefix.lines[cnt]. "G"
endfu

fu! changes#CurrentHunk() "{{{1
    if changes#MoveToNextChange(0) == "\<Esc>"
	" outside of a hunk
	return "\<Esc>"
    else
	return "[ho]h"
    endif
endfu
" Modeline "{{{1
" vi:fdm=marker fdl=0
