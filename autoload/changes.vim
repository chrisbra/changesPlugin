" Changes.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.8
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Mon, 19 Apr 2010 15:10:16 +0200


" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 8 :AutoInstall: ChangesPlugin.vim

" Documentation:"{{{1
" See :h ChangesPlugin.txt

" Check preconditions"{{{1
fu! changes#Check()
    if !has("diff")
	call changes#WarningMsg(1,"Diff support not available in your Vim version.")
	call changes#WarningMsg(1,"changes plugin will not be working!")
	finish
    endif

    if  !has("signs")
	call changes#WarningMsg(1,"Sign Support support not available in your Vim version.")
	call changes#WarningMsg(1,"changes plugin will not be working!")
	finish
    endif

    if !executable("diff") || executable("diff") == -1
	call changes#WarningMsg(1,"No diff executable found")
	call changes#WarningMsg(1,"changes plugin will not be working!")
	finish
    endif

    " Check for the existence of unsilent
    if exists(":unsilent")
	let s:cmd='unsilent echomsg'
    else
	let s:cmd='echomsg'
    endif

endfu

fu! changes#WarningMsg(mode,msg)"{{{1
    if type(a:msg) == 1
	let msg=["Changes.vim: " . a:msg]
    else
	let msg=["Changes.vim: " . a:msg[0]] + a:msg[1:]
    endif

    if a:mode
	echohl WarningMsg
    endif
    for line in msg
	    exe s:cmd "line"
    endfor

    if a:mode
	echohl Normal
	let v:errmsg=msg[0]
    endif
endfu

fu! changes#Output()"{{{1
    if s:verbose
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
    " Only check the first time this file is loaded
    " It should not be neccessary to check every time
    if !exists("s:precheck")
	call changes#Check()
	let s:precheck=1
    endif
    let s:hl_lines = (exists("g:changes_hl_lines")  ? g:changes_hl_lines   : 0)
    let s:autocmd  = (exists("g:changes_autocmd")   ? g:changes_autocmd    : 0)
    let s:verbose  = (exists("g:changes_verbose")   ? g:changes_verbose    : 1)
    " Buffer queue, that will be displayed.
    let s:msg      = []
    " Check against a file in a vcs system
    let s:vcs      = (exists("g:changes_vcs_check") ? g:changes_vcs_check  : 0)
    if !exists("s:vcs_cat")
	let s:vcs_cat  = {'git': 'show HEAD:', 
			 \'bazaar': 'cat ', 
			 \'cvs': '-q update -p ',
			 \'svn': 'cat ',
			 \'subversion': 'cat ',
			 \'svk': 'cat ',
			 \'hg': 'cat ',
			 \'mercurial': 'cat '}
    endif

    " Settings for Version Control
    if s:vcs
       if !exists("g:changes_vcs_system")
	   call changes#WarningMsg(1,"Please specify which VCS to use. See :h changes-vcs.")
	   call changes#WarningMsg(1,"VCS check will be disabled for now.")
	   throw 'changes:NoVCS'
	   sleep 2
	   let s:vcs=0
      endif
      let s:vcs_type  = g:changes_vcs_system
      if get(s:vcs_cat, s:vcs_type)
	   call changes#WarningMsg(1,"Don't know VCS " . s:vcs_type)
	   call changes#WarningMsg(1,"VCS check will be disabled for now.")
	   sleep 2
	   let s:vcs=0
      endif
      if !exists("s:temp_file")
	  let s:temp_file=tempname()
      endif
    endif

    " This variable is a prefix for all placed signs.
    " This is needed, to not mess with signs placed by the user
    let s:sign_prefix = 99
    let s:signs={}
    let s:ids={}
    let s:signs["add"] = "texthl=DiffAdd text=+ texthl=DiffAdd " . ( (s:hl_lines) ? " linehl=DiffAdd" : "")
    let s:signs["del"] = "texthl=DiffDelete text=- texthl=DiffDelete " . ( (s:hl_lines) ? " linehl=DiffDelete" : "")
    let s:signs["ch"] = "texthl=DiffChange text=* texthl=DiffChange " . ( (s:hl_lines) ? " linehl=DiffChange" : "")

    let s:ids["add"]   = hlID("DiffAdd")
    let s:ids["del"]   = hlID("DiffDelete")
    let s:ids["ch"]    = hlID("DiffChange")
    let s:ids["ch2"]   = hlID("DiffText")
    call changes#DefineSigns()
    call changes#AuCmd(s:autocmd)
endfu

fu! changes#AuCmd(arg)"{{{1
    if s:autocmd && a:arg
	augroup Changes
		autocmd!
		au CursorHold * :call changes#UpdateView()
	augroup END
    else
	augroup Changes
		autocmd!
	augroup END
    endif
endfu

fu! changes#DefineSigns()"{{{1
    exe "sign define add" s:signs["add"]
    exe "sign define del" s:signs["del"]
    exe "sign define ch"  s:signs["ch"]
endfu

fu! changes#CheckLines(arg)"{{{1
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
	" Check for deleted lines in the diffed scratch buffer
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

fu! changes#UpdateView()"{{{1
    if !exists("b:changes_chg_tick")
	let b:changes_chg_tick = 0
    endif
    " Only update, if there have been changes to the buffer
    if  b:changes_chg_tick != b:changedtick
	call changes#GetDiff()
    endif
endfu

fu! changes#GetDiff()"{{{1
    try
	call changes#Init()
    catch changes:NoVCS
	let s:verbose = 0
	return
    endtry

    if empty(bufname(''))
	call changes#WarningMsg(1,"The buffer does not contain a name. Check aborted!")
	let s:verbose = 0
	return
    endif


    " Save some settings
    let o_lz   = &lz
    let o_fdm  = &fdm
    let b:ofdc = &fdc
    " Lazy redraw
    setl lz
    " For some reason, getbufvar/setbufvar do not work, so
    " we use a temporary script variable here
    let s:temp = {'del': []}
    " Delete previously placed signs
    "sign unplace *
    call changes#UnPlaceSigns()
    let b:diffhl={'add': [], 'del': [], 'ch': []}
    try
	call changes#MakeDiff()
	call changes#CheckLines(1)
	" Switch to other buffer and check for deleted lines
	noa wincmd p
	call changes#CheckLines(0)
	noa wincmd p
	let b:diffhl['del'] = s:temp['del']
	" Check for empty dict of signs
	if (empty(values(b:diffhl)[0]) && 
	   \empty(values(b:diffhl)[1]) && 
	   \empty(values(b:diffhl)[2]))
	    call add(s:msg, 'No differences found!')
	else
	    call changes#PlaceSigns(b:diffhl)
	endif
	call changes#DiffOff()
	" I assume, the diff-mode messed up the folding settings,
	" so we need to restore them here
	"
	" Should we also restore other fold related settings?
	let &fdm=o_fdm
	if b:ofdc ==? 1
	    " When foldcolumn is 1, folds won't be shown because of
	    " the signs, so increasing its value by 1 so that folds will
	    " also be shown
	    let &fdc += 1
	endif
	let b:changes_view_enabled=1
    catch /^changes/
	let b:changes_view_enabled=0
	let s:verbose = 0
    finally
	let &lz=o_lz
	redraw!
	if s:vcs && b:changes_view_enabled
	    call add(s:msg,"Check against " . fnamemodify(expand("%"),':t') . " from " . g:changes_vcs_system)
	    call changes#WarningMsg(0,s:msg)
	endif
    endtry
endfu

fu! changes#PlaceSigns(dict)"{{{1
    for [ id, lines ] in items(a:dict)
	for item in lines
	    exe "sign place " s:sign_prefix . item . " line=" . item . " name=" . id . " buffer=" . bufnr('')
	endfor
    endfor
endfu

fu! changes#UnPlaceSigns()"{{{1
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

fu! changes#MakeDiff()"{{{1
    " Get diff for current buffer with original
    noa vert new
    set bt=nofile
    if !s:vcs
	r #
    else
	try
	    if s:vcs_cat[s:vcs_type] == 'git'
		let git_rep_p = s:ReturnGitRepPath()
	    else
		let git_rep_p = ''
	    endif
	    exe ':silent !' s:vcs_type s:vcs_cat[s:vcs_type] .  git_rep_p . expand("#") '>' s:temp_file
	    let fsize=getfsize(s:temp_file)
	    if fsize == 0
		call delete(s:temp_file)
		call changes#WarningMsg(1,"Couldn't get VCS output, aborting")
		:q!
		throw "changes:abort"
	    endif
	    exe ':r' s:temp_file
	    call delete(s:temp_file)
        catch /^changes: No git Repository found/
	    call changes#WarningMsg(1,"Unable to find git Top level repository.")
	    echo v:errmsg
	    :q!
	    throw "changes:abort"
	endtry
    endif
    0d_
    diffthis
    noa wincmd p
    diffthis
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
	return file[ldir :]
    endif
endfu


fu! changes#DiffOff()"{{{1
    " Turn off Diff Mode and close buffer
    wincmd p
    diffoff!
    q
endfu

fu! changes#CleanUp()"{{{1
    " only delete signs, that have been set by this plugin
    call changes#UnPlaceSigns()
    for key in keys(s:signs)
	exe "sign undefine " key
    endfor
    if s:autocmd
	call changes#AuCmd(0)
    endif
endfu

fu! changes#TCV()"{{{1
    if  exists("b:changes_view_enabled") && b:changes_view_enabled
        DC
        let &fdc=b:ofdc
        let b:changes_view_enabled = 0
        echo "Hiding changes since last save"
    else
	call changes#GetDiff()
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
	exe ":vimgrep /".join(b, '\|').'/gj' expand("%")
	copen
    else
	" This should not happen!
	call changes#WarningMsg(1,"Pattern not found!")
    endif
endfun

" Modeline "{{{1
" vi:fdm=marker fdl=0
