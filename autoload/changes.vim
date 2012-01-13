" Changes.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.11
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Tue, 04 May 2010 21:16:28 +0200

" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 11 :AutoInstall: ChangesPlugin.vim

" Documentation:"{{{1
" See :h ChangesPlugin.txt

" Check preconditions"{{{1
fu! s:Check()
    " Check for the existence of unsilent
    if exists(":unsilent")
	let s:echo_cmd='unsilent echomsg'
    else
	let s:echo_cmd='echomsg'
    endif

    if !has("diff")
	call add(s:msg,"Diff support not available in your Vim version.")
	call add(s:msg,"changes plugin will not be working!")
	throw 'changes:abort'
    endif

    if  !has("signs")
	call add(s:msg,"Sign Support support not available in your Vim version.")
	call add(s:msg,"changes plugin will not be working!")
	throw 'changes:abort'
    endif

    if !executable("diff") || executable("diff") == -1
	call add(s:msg,"No diff executable found")
	call add(s:msg,"changes plugin will not be working!")
	throw 'changes:abort'
    endif


    let s:sign_prefix = 99
    let s:ids={}
    let s:ids["add"]   = hlID("DiffAdd")
    let s:ids["del"]   = hlID("DiffDelete")
    let s:ids["ch"]    = hlID("DiffChange")
    let s:ids["ch2"]   = hlID("DiffText")

endfu

fu! s:WarningMsg()"{{{1
    redraw!
    if !empty(s:msg)
	let msg=["Changes.vim: " . s:msg[0]] + s:msg[1:]
	echohl WarningMsg
	for mess in msg
		exe s:echo_cmd "mess"
	endfor

	echohl Normal
	let v:errmsg=msg[0]
    endif
endfu

fu! changes#Output(force)"{{{1
    if s:verbose || a:force
	echohl Title
	echo "Differences will be highlighted like this:"
	echohl Normal
	echo "========================================="
	echohl DiffAdd
	echo "+ Added Lines"
	echohl DiffDelete
	echo "- Deleted Lines"
	echohl DiffChange
	echo "* Changed Lines"
	echohl Normal
    endif
endfu

fu! changes#Init()"{{{1
    " Message queue, that will be displayed.
    let s:msg      = []
    " Only check the first time this file is loaded
    " It should not be neccessary to check every time
    if !exists("s:precheck")
	call s:Check()
	let s:precheck=1
    endif
    let s:hl_lines = (exists("g:changes_hl_lines")  ? g:changes_hl_lines   : 0)
    let s:autocmd  = (exists("g:changes_autocmd")   ? g:changes_autocmd    : 0)
    let s:verbose  = (exists("g:changes_verbose")   ? g:changes_verbose    : (exists("s:verbose") ? s:verbose : 1))
    " Check against a file in a vcs system
    let s:vcs      = (exists("g:changes_vcs_check") ? g:changes_vcs_check  : 0)
    let b:vcs_type = (exists("g:changes_vcs_system")? g:changes_vcs_system : s:GuessVCSSystem())
    if !exists("s:vcs_cat")
	let s:vcs_cat  = {'git': 'show HEAD:', 
			 \'bzr': 'cat ', 
			 \'cvs': '-q update -p ',
			 \'svn': 'cat ',
			 \'subversion': 'cat ',
			 \'svk': 'cat ',
			 \'hg': 'cat ',
			 \'mercurial': 'cat '}
    endif

    " Settings for Version Control
    if s:vcs
      if get(s:vcs_cat, b:vcs_type, 'NONE') == 'NONE'
	   call add(s:msg,"Don't know VCS " . b:vcs_type)
	   call add(s:msg,"VCS check will be disabled for now.")
	   let s:vcs=0
	   throw 'changes:NoVCS'
      endif
      if !executable(b:vcs_type)
	   call add(s:msg,"Executable " . b:vcs_type . "not found! Aborting.")
	   throw "changes:abort"
      endif
      if !exists("s:temp_file")
	  let s:temp_file=tempname()
      endif
    endif
    let s:nodiff=0

    " This variable is a prefix for all placed signs.
    " This is needed, to not mess with signs placed by the user
    let s:signs={}
    let s:signs["add"] = "text=+ texthl=DiffAdd " . ( (s:hl_lines) ? " linehl=DiffAdd" : "")
    let s:signs["del"] = "text=- texthl=DiffDelete " . ( (s:hl_lines) ? " linehl=DiffDelete" : "")
    let s:signs["ch"] = "text=* texthl=DiffChange " . ( (s:hl_lines) ? " linehl=DiffChange" : "")

    " Delete previously placed signs
    call s:UnPlaceSigns()
    call s:DefineSigns()
    call s:AuCmd(s:autocmd)
endfu

fu! s:AuCmd(arg)"{{{1
    if a:arg
	augroup Changes
		autocmd!
		let s:verbose=0
		au InsertLeave,CursorHold * :call s:UpdateView()
	augroup END
    else
	augroup Changes
		autocmd!
	augroup END
    endif
endfu

fu! s:DefineSigns()"{{{1
    for key in keys(s:signs)
	exe "silent! sign undefine " key
	exe "sign define" key s:signs[key]
    endfor
endfu

fu! s:CheckLines(arg)"{{{1
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

fu! s:UpdateView()"{{{1
    if !exists("b:changes_chg_tick")
	let b:changes_chg_tick = 0
    endif
    " Only update, if there have been changes to the buffer
    if  b:changes_chg_tick != b:changedtick
	" Turn off displaying the Caption
	let s:verbose=0
	call changes#GetDiff(1)
    endif
endfu

fu! changes#GetDiff(arg)"{{{1
    " a:arg == 1 Create signs
    " a:arg == 2 Show Overview Window
    " a:arg == 3 Stay in diff mode
    try
	call changes#Init()
    catch /^changes:/
	let s:verbose = 0
	call s:WarningMsg()
	return
    endtry

    " Does not make sense to check an empty buffer
    if empty(bufname(''))
	call add(s:msg,"The buffer does not contain a name. Check aborted!")
	let s:verbose = 0
	return
    endif

    " Save some settings
    " fdm, wrap, and fdc will be reset by :diffoff!
    let o_lz   = &lz
    let o_fdm  = &fdm
    let o_fdc  = &fdc
    let o_wrap = &wrap
    " Lazy redraw
    setl lz
    " For some reason, getbufvar/setbufvar do not work, so
    " we use a temporary script variable here
    let s:temp = {'del': []}
    let b:diffhl={'add': [], 'del': [], 'ch': []}
    try
	call s:MakeDiff()
	call s:CheckLines(1)
	" Switch to other buffer and check for deleted lines
	noa wincmd p
	call s:CheckLines(0)
	noa wincmd p
	let b:diffhl['del'] = s:temp['del']
	call s:CheckDeletedLines()
	" Check for empty dict of signs
	if (empty(values(b:diffhl)[0]) && 
	   \empty(values(b:diffhl)[1]) && 
	   \empty(values(b:diffhl)[2]))
	    call add(s:msg, 'No differences found!')
	    let s:verbose=0
	    let s:nodiff=1
	else
	    call s:PlaceSigns(b:diffhl)
	endif
	if a:arg !=? 3  || s:nodiff
	    call s:DiffOff()
	endif
	" :diffoff resets some options (see :h :diffoff
	" so we need to restore them here
	" We don't reset the fdm, in case we are staying in diff mode
	if a:arg != 3 || s:nodiff
	    let &fdm=o_fdm
	    if  o_fdc ==? 1
		" When foldcolumn is 1, folds won't be shown because of
		" the signs, so increasing its value by 1 so that folds will
		" also be shown
		let &fdc += 1
	    else
		let &fdc = o_fdc
	    endif
	    let &wrap = o_wrap
	    let b:changes_view_enabled=1
	endif
	if a:arg ==# 2
	   call s:ShowDifferentLines()
	   let s:verbose=0
	endif
    catch /^changes/
	call s:DiffOff()
	let b:changes_view_enabled=0
	let s:verbose = 0
    finally
	let &lz=o_lz
	if s:vcs && exists("b:changes_view_enabled") && b:changes_view_enabled
	    call add(s:msg,"Check against " . fnamemodify(expand("%"),':t') . " from " . b:vcs_type)
	endif
	call s:WarningMsg()
	call changes#Output(0)
    endtry
endfu

fu! s:PlaceSigns(dict)"{{{1
    for [ id, lines ] in items(a:dict)
	for item in lines
	    " One special case could occur:
	    " You could delete the last lines. In that case, we couldn't place
	    " here the deletion marks. If this happens, palce the deletion
	    " marks on the last line
	    "if item > line('$')
	"	let item=line('$')
	"    endif
	    exe "sign place " s:sign_prefix . item . " line=" . item . " name=" . id . " buffer=" . bufnr('')
	endfor
    endfor
endfu

fu! s:UnPlaceSigns()"{{{1
    redir => a
    silent sign place
    redir end
    let b=split(a,"\n")
    let b=filter(b, 'v:val =~ "id=".s:sign_prefix')
    let b=map(b, 'matchstr(v:val, ''id=\zs\d\+'')')
    for id in b
	exe "sign unplace" id
    endfor
endfu

fu! s:MakeDiff()"{{{1
    " Get diff for current buffer with original
    let o_pwd = getcwd()
    let bnr = bufnr('%')
    let ft  = &l:ft
    noa vert new
    set bt=nofile
    if !s:vcs
	r #
	let &l:ft=ft
    else
	let vcs=getbufvar(bnr, 'vcs_type')
	try
	    if vcs == 'git'
		let git_rep_p = s:ReturnGitRepPath()
	    elseif vcs == 'cvs'
		" I am not sure, if this is the best way
		" to query CVS. But just to make sure, 
		" we are in the right path and we don't have
		" to consider CVSROOT
		exe 'lcd' fnamemodify(expand('#'), ':p:h')
		let git_rep_p = ' '
	    else
		let git_rep_p = ' '
	    endif
	    exe ':silent !' vcs s:vcs_cat[vcs] .  git_rep_p . expand("#") '>' s:temp_file
	    let fsize=getfsize(s:temp_file)
	    if fsize == 0
		call delete(s:temp_file)
		call add(s:msg,"Couldn't get VCS output, aborting")
		wincmd p
		throw "changes:abort"
	    endif
	    exe ':r' s:temp_file
	    call delete(s:temp_file)
        catch /^changes: No git Repository found/
	    call add(s:msg,"Unable to find git Top level repository.")
	    echo v:errmsg
	    wincmd p
	    throw "changes:abort"
	endtry
    endif
    0d_
    diffthis
    noa wincmd p
    diffthis
    if s:vcs && exists("vcs") && vcs=='cvs'
	exe "cd "  o_pwd
    endif
endfu

fu! s:ReturnGitRepPath() "{{{1
    " return the top level of the repository path. This is needed, so
    " git show will correctly return the file
    let file  =  fnamemodify(expand("#"), ':p')
    let path  =  fnamemodify(file, ':h')
    let dir   =  finddir('.git',path.';')
    if empty(dir)
	throw 'changes: No git Repository found'
    else
	let ldir  =  strlen(substitute(dir, '.', 'x', 'g'))-4
	if ldir
	    return file[ldir :]
	else
	    return ''
	endif
    endif
endfu


fu! s:DiffOff()"{{{1
    " Turn off Diff Mode and close buffer
    wincmd p
    diffoff!
    q
endfu

fu! changes#CleanUp()"{{{1
    " only delete signs, that have been set by this plugin
    call s:UnPlaceSigns()
    for key in keys(s:signs)
	exe "sign undefine " key
    endfor
    if s:autocmd
	call s:AuCmd(0)
    endif
endfu

fu! changes#TCV()"{{{1
    if  exists("b:changes_view_enabled") && b:changes_view_enabled
        :DC
	if exists("b:ofdc")
	    let &fdc=b:ofdc
	endif
        let b:changes_view_enabled = 0
        echo "Hiding changes since last save"
    else
	call changes#GetDiff(1)
        let b:changes_view_enabled = 1
        echo "Showing changes since last save"
    endif
endfunction


fu! s:ShowDifferentLines()"{{{1
    redir => a
    silent sign place
    redir end
    let b=split(a,"\n")
    let b=filter(b, 'v:val =~ "id=".s:sign_prefix')
    let b=map(b, 'matchstr(v:val, ''line=\zs\d\+'')')
    let b=map(b, '''\%(^\%''.v:val.''l\)''')
    if !empty(b)
	exe ":silent! lvimgrep /".join(b, '\|').'/gj' expand("%")
	lw
    else
	" This should not happen!
	call setloclist(winnr(),[],'a')
	lclose
    endif
endfun

fu! s:GuessVCSSystem() "{{{1
    " Check global config variable
    if exists("g:changes_vcs_system")
	let vcs=matchstr(g:changes_vcs_system, '\(git\)\|\(hg\)\|\(bzr\)\|\(svk\)\|\(cvs\)\|\(svn\)')
	if vcs
	    return vcs
	endif
    endif
    let file = fnamemodify(expand("%"), ':p')
    let path = fnamemodify(file, ':h')
    " First let's try if there is a CVS dir
    if isdirectory(path . '/CVS')
	return 'cvs'
    elseif isdirectory(path . '/.svn')
	return 'svn'
    endif
    if !empty(finddir('.git',path.';'))
	return 'git'
    elseif !empty(finddir('.hg',path.';'))
	return 'hg'
    elseif !empty(finddir('.bzr',path.';'))
	return 'bzr'
    else
	"Fallback: svk
	return 'svk'
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


" Modeline "{{{1
" vi:fdm=marker fdl=0
