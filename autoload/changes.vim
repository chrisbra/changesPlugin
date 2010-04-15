" Changes.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.6
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: 2010/04/13
" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 6 :AutoInstall: ChangesPlugin.vim

" Documentation:"{{{1
" To see differences with your file, exexute:
" :EnableChanges
"
" The following variables will be accepted:
"
" g:changes_hl_lines
" If set, all lines will be highlighted, else
" only an indication will be displayed on the first column
" (default: 0)
"
" g:changes_autocmd
" Updates the indication for changed lines automatically,
" if the user does not press a key for 'updatetime' seconds when
" Vim is not in insert mode. See :h 'updatetime'
" (default: 0)
"
" g:changes_verbose
" Output a short description, what these colors mean
" (default: 1)
"
" Colors for indicating the changes
" By default changes.vim displays deleted lines using the hilighting
" DiffDelete, added lines using DiffAdd and modified lines using
" DiffChange.
" You can see how these are defined, by issuing
" :hi DiffAdd
" :hi DiffDelete
" :hi DiffChange
" See also the help :h hl-DiffAdd :h hl-DiffChange and :h hl-DiffDelete
"
" If you'd like to change these colors, simply change these hilighting items
" see :h :hi

" Check preconditions"{{{1
fu changes#Check()
    if !has("diff")
	call changes#WarningMsg("Diff support not available in your Vim version.")
	call changes#WarningMsg("changes plugin will not be working!")
	finish
    endif

    if  !has("signs")
	call changes#WarningMsg("Sign Support support not available in your Vim version.")
	call changes#WarningMsg("changes plugin will not be working!")
	finish
    endif

    if !executable("diff") || executable("diff") == -1
	call changes#WarningMsg("No diff executable found")
	call changes#WarningMsg("changes plugin will not be working!")
	finish
    endif
endfu

fu! changes#WarningMsg(msg)"{{{1
    echohl WarningMsg
    echo a:msg
    echohl Normal
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
    let s:hl_lines = (exists("g:changes_hl_lines") ? g:changes_hl_lines : 0)
    let s:autocmd  = (exists("g:changes_autocmd")  ? g:changes_autocmd  : 0)
    let s:verbose  = (exists("g:changes_verbose")  ? g:changes_verbose  : 1)
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
    call changes#Check()
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
    call changes#Init()
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
"	for key in keys(s:signs)
"	    exe "sign unplace " key
"	endfor
    call changes#MakeDiff()
    let b:diffhl={'add': [], 'del': [], 'ch': []}
    call changes#CheckLines(1)
    " Switch to other buffer and check for deleted lines
    noa wincmd p
    call changes#CheckLines(0)
    noa wincmd p
    let b:diffhl['del'] = s:temp['del']
    call changes#PlaceSigns(b:diffhl)
    call changes#DiffOff()
    redraw
    let &lz=o_lz
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
    r #
    0d_
    diffthis
    noa wincmd p
    diffthis
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


" Modeline "{{{1
" vi:fdm=marker fdl=0
