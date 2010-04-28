" Vimball Archiver by Charles E. Campbell, Jr., Ph.D.
UseVimball
finish
autoload/changes.vim	[[[1
483
" Changes.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.10
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Wed, 28 Apr 2010 08:25:37 +0200


" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 10 :AutoInstall: ChangesPlugin.vim

" Documentation:"{{{1
" See :h ChangesPlugin.txt

" Check preconditions"{{{1
fu! s:Check()
    if !has("diff")
	call add(s:msg,"Diff support not available in your Vim version.")
	call add(s:msg,"changes plugin will not be working!")
	finish
    endif

    if  !has("signs")
	call add(s:msg,"Sign Support support not available in your Vim version.")
	call add(s:msg,"changes plugin will not be working!")
	finish
    endif

    if !executable("diff") || executable("diff") == -1
	call add(s:msg,"No diff executable found")
	call add(s:msg,"changes plugin will not be working!")
	finish
    endif

    " Check for the existence of unsilent
    if exists(":unsilent")
	let s:echo_cmd='unsilent echomsg'
    else
	let s:echo_cmd='echomsg'
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

fu! s:Init()"{{{1
    " Only check the first time this file is loaded
    " It should not be neccessary to check every time
    if !exists("s:precheck")
	call s:Check()
	let s:precheck=1
    endif
    let s:hl_lines = (exists("g:changes_hl_lines")  ? g:changes_hl_lines   : 0)
    let s:autocmd  = (exists("g:changes_autocmd")   ? g:changes_autocmd    : 0)
    let s:verbose  = (exists("g:changes_verbose")   ? g:changes_verbose    : (exists("s:verbose") ? s:verbose : 1))
    " Message queue, that will be displayed.
    let s:msg      = []
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
    if s:autocmd && a:arg
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
	call s:Init()
    catch changes:NoVCS
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
	else
	    call s:PlaceSigns(b:diffhl)
	endif
	if a:arg !=? 3
	    call s:DiffOff()
	endif
	" :diffoff resets some options (see :h :diffoff
	" so we need to restore them here
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
    noa vert new
    set bt=nofile
    if !s:vcs
	r #
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
doc/ChangesPlugin.txt	[[[1
261
*ChangesPlugin.txt*  Print indication of changed lines for a buffer 

Author:  Christian Brabandt <cb@256bit.org>
Version: 0.10 Wed, 28 Apr 2010 08:25:37 +0200
Copyright: (c) 2010 by Christian Brabandt 	 *ChangesPlugin-copyright*
	   The VIM LICENSE applies to ChangesPlugin.txt (see |copyright|)
	   except use unicode instead of "Vim".  NO WARRANTY, EXPRESS OR
	   IMPLIED.  USE AT-YOUR-OWN-RISK.

==============================================================================
1. Contents                          			      *ChangesPlugin*

  1.  Contents......................................: |ChangesPlugin|
  2.  Manual........................................: |ChangesPlugin-manual|
  3.  Configuration.................................: |ChangesPlugin-Config|
   3.1 Highlighting whole lines.....................: |ChangesPlugin-hlLine|
   3.2 Auto-refresh changes.........................: |ChangesPlugin-aucmd|
   3.3 Show the meaning of the indicator bars.......: |ChangesPlugin-bars|
   3.4 Specify different colors.....................: |ChangesPlugin-colors|
   3.5 Check against a file in a VCS................: |ChangesPlugin-VCS|
  4.  ChangesPlugin Feedback........................: |ChangesPlugin-Feedback|
  5.  ChangesPlugin History.........................: |ChangesPlugin-history|

==============================================================================

                                                       *ChangesPlugin-manual*
2. Functionality

This plugin was written to help visualize which lines have been changes since
editing started for a file. The plugin was inspired by so called changed-bars,
available at other editors, such as Embarcadero C++ Builder (there it is
called Change Bars, see:
http://edn.embarcadero.com/article/33453#6PersonalDeveloperProductivity)
or Visual Studio where it is called indicator margin (see
http://blog.eveningcreek.com/?p=151).

ChangesPlugin.vim uses the |diff|-feature of vim and compares the actual
buffer with it's saved state. In order to highlight the indicator signs at the
first column, its using |signs|. For newly added lines, the first column will
be displayed with a leading '+' and highlighted using the DiffAdd highlighting
(see |hl-DiffAdd|), deleted lines will be indicated by a '-' with a
DiffDelete highlighting (see |hl-DiffDelete|) and modified lines will be
displayed using '*' and a DiffChange highlighting (see |hl-DiffChange|).

Note, that a '-' will be shown on the next line after the deleted lines. A
range of consecutive deleted lines will be displayed by only one '-'

This means, that in order to use this plugin you need a vim, that was built
with |+signs|-support and |+diff|-support and you also need an executable diff
command. If neither of these conditions are met, changePlugin.vim will issue a
warning and abort.

							 *:EC* *:EnableChanges*
By default the plugin is not enabled. To enable it enter >
    :EnableChanges
When you run this command, ChangesPlugin.vim diffs the current file agains
its saved file on disk and displays the changes in the first column.

Alternatively, you can enter the shortcut >
     :EC
which basically calls :EnableChanes

							 *:DC* *:DisableChanges*
If you want to disable the plugin, enter >
    :DisableChanges
or alternatively, you can enter the shortcut >
     :DC
and the Display of Changes will be disabled.

						     *:TCV* *:ToggleChangeView*
You can toggle, between turning on and off the indicator bars, using >
     :ToggleChangeView
or alternatively: >
     :TCV
to toggle the display of indicator bars.

						     *:CC* *:ChangesCpation*
You are probably wondering, what those strange looking signs mean. You can use
either >
    :CC
or >
    :ChangesCaptions
to let the Plugin display a small caption, so you know what each sign means
and how they are colored.

						 *:CL* *:ChangesLineOverview*
If you are editing a huge file with several hundreds of lines, it may be hard
to find the lines that have been changed. >
    :CL
or >
    :ChangesLineOverview	
provide an easy view to only see all modified lines. This will open the
|location-list| buffer where you can easily see the affected lines. Pushing enter
on any line, allows you to easily jump to that line in the buffer.

						 *:CD* *:ChangesDiffMode*
You might want to keep the diff-window open, so you can use it for modifying
your buffer using e.g. |:diffput| or |:diffget|
Therefore ChangesPlugin defines the two commands >
    :CD
and >
    :ChangesDiffMode
If you issue any of these commands, a vertical split buffer will open,
that contains the changes from either your VCS or from the unmodified buffer
as it is saved on disk. See |copy-diffs| for how to merge changes between
those two buffers.

==============================================================================
							*ChangesPlugin-Config*
3. Configuring ChangesPlugin.vim

There are several different configuration options available.

							*ChangesPlugin-hlLine*
2.1 Highlighte the whole line
By default, ChangesPlugin.vim will only indicate a change in the first column.
Setting g:changes_hl_lines to 1 will highlight the whole line. By default this
variable is unset (which is the same as setting it to 0).
If you'd like to have this, set this variable in your |.vimrc| >
    :let g:changes_hl_lines=1

							*ChangesPlugin-aucmd*
3.2 Auto-refresh the changes
By default ChangesPlugin.vim will not automatically update the view. You can
however configure it to do so. This will use an |CursorHold| autocommand to
update the indicator signs after |'updatetime'| seconds in Normal mode when
no key is pressed. To enable this feature, put this in your |.vimrc| >
    let g:changes_autocmd=1

This autocommand checks, whether there have been changes to the file, or else
it won't update the view.

							*ChangesPlugin-bars*
3.3 Show what the indicator signs mean.
By default, whenever you run |:EnableChanges|, changesVim will print a short
status message, what each sign means. If you don't want this, put this in your
|.vimrc| >
    :let g:changes_verbose=0
and achangesPlugin won't display this message again. You can always issue the
|CL| command to find out, what each sign means.
							*ChangesPlugin-colors*

3.4 Specify different colors.
changesVim uses the highlighting used for |diff| mode to indicate the change
in a buffer. This is consistent, since when you're already used to |vimdiff|
you'll probably also know the highlighting. If for any reason you do not like
the colors, you have to define your own highlighting items.
If for example you want the DiffAdd highlighting to be displayed like White on
a Blue background, you can define it as follows in your |.vimrc| >

    :hi DiffAdd term=bold ctermbg=4 guibg=DarkBlue

In the same way, you can change DiffDelete for indicating deleted lines and
DiffChange for indicating modified lines. You can also specify your favorite
highlighting colors using your own build |colorscheme|.

							     *ChangesPlugin-VCS*
3.5 Check differences against a checked-in file from a VCS

Warning: This feature is rather experimental. So use it with care. 

You can configure ChangesPlugin to check the differrences of the current
buffer not only against the file stored on disk, but rather query a Version
Control System (VCS) for its latest version and indicate changes based on
this version. 

Currently, ChangesPlugin supports these VCS Systems:
    - git
    - cvs
    - bzr
    - svn
    - svk
    - hg

To enable this feature, you need to set the variable g:changes_vcs_check to
1. ChangesPlugin will then try to auto-detect, which of the above supported
VCS-Systems is in use. That means, if it can't detect neither of git, cvs,
svn, bzr or hg it will assume you are using svk. This may fail obviously, so
you can always force ChangesPlugin to use any of the above by setting the 
g:changes_vcs_system Variable.

To enable this feature, you need to set the g:changes_vcs_check variable to 1.
The following example enables this feature and ensures, EnablePlugin is using
git as VCS, so these lines have been entered in the |.vimrc| >
    :let g:changes_vcs_check=1
    :let g:changes_vcs_system='git'

Note, that depending on the VCS System you use, this might slow down
ChangesPlugin significantly. Especially CVS seems to be very slow.

Note also, that setting g:changes_vcs_system is setting a global variable (see
|g:-var|) and therefore would set the VCS for every buffer opened in vim (thus
you could use changesPlugin only with one single VCS). However, guessing the
VCS System should work fairely well and in case it doesn't, please report a
bug to the maintainer of the plugin. Setting g:changes_vcs_check will however
disable the check against the on-disk version of a buffer.

==============================================================================
4. ChangesPlugin Feedback			    *ChangesPlugin-feedback*

Feedback is always welcome. If you like the plugin, please rate it at the
vim-page:
http://www.vim.org/scripts/script.php?script_id=3052

You can also follow the development of the plugin at github:
http://github.com/chrisbra/changesPlugin

Please don't hesitate to report any bugs to the maintainer, mentioned in the
third line of this document.

==============================================================================
5. ChangesPlugin History				*ChangesPlugin-history*
    0.10: Apr 28, 2010: NF: Fixed Issue 1 from github
                            (http://github.com/chrisbra/changesPlugin/issues/1/find)
    0.9: Apr 24, 2010:  NF: You can now use different VCS Systems for each
                            buffer you are using.
			NF: Stay in diff mode
			BF: Fix the display of deleted signs
			BF: Undefining old signs, so that changing
			    g:changes_hl_lines works
			BF: Some more error handling.
			NF: Show an overview for changed lines in location-list
			    (|:CL|)
			NF: Show what each sign means using |:CC|
    0.8: Apr 22, 2010:  NF: Renamed the helpfile, to make it more obvious, 
			that it refers to a plugin
			NF: Outputting name of checked file, if checking
			    against VCS
			BF: Don't check for empty files.
			BF: Reworked the Message function
			BF: Don't try to place signs, if there are no
			    differences
			    (unreleased, VCS successfully tested with
			     git, hg, svn, cvs, bzr)
    0.7: Apr 19, 2010:  NF: Check against a file in a VCS
			    (unreleased, first working version,
			    needs to be checked for each VCS)
    0.6: Apr 12, 2010:  BF: fixed a missing highlight for DiffText
    0.5: Apr 12, 2010:  BF: error when trying to access b:diffhl in the
			    scratch buffer. This should be fixed now (thanks
			    Jeet Sukumaran!)
			BF: Use the correct highlighting groups (thanks Jeet
			    Sukumaran!)
    0.4: Apr 12, 2010:  NF: |ToggleChangesView|
			NF: The autocommand checks, if the buffer has been
			    modified, since the last time.
			BF: Do not mess with signs, that have not been placed
			    by ChangesPlugin.vim
			BF: CleanUp was seriously messed up (sorry, I must
			    have been asleep, when writing that)
			BF: Take care of 'foldcolumn' setting, which would be
			    overwritten by the signs-column
    0.3: Apr 11, 2010:  BF: redraw, so that the diff window will not be
			    displayed
			NF: enabled GLVS (see |GLVS|)
    0.2: Apr 11, 2010:	Added Documentation
			created an autoload version
    0.1: Apr 10, 2010:	First working version

==============================================================================
vim:tw=78:ts=8:ft=help
plugin/changesPlugin.vim	[[[1
52
" ChangesPlugin.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.10
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Wed, 28 Apr 2010 08:25:37 +0200


" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 10 :AutoInstall: ChangesPlugin.vim


" ---------------------------------------------------------------------
"  Load Once: {{{1
if &cp || exists("g:loaded_changes")
 finish
endif
let g:loaded_changes       = 1
let s:keepcpo              = &cpo
set cpo&vim

let s:autocmd  = (exists("g:changes_autocmd")  ? g:changes_autocmd  : 0)
" ------------------------------------------------------------------------------
" Public Interface: {{{1

" Define the Shortcuts:
com! DC	 DisableDisplayChanges
com! EC	 EnableDisplayChanges
com! TCV ToggleChangeView
com! CC  ChangesCaption
com! CL  ChangesLinesOverview
com! CD  ChangesDiffMode

com! EnableDisplayChanges	call changes#GetDiff(1)
com! DisableDisplayChanges	call changes#CleanUp()
com! ToggleChangeView		call changes#TCV()
com! ChangesCaption		call changes#Output(1)
com! ChangesLinesOverview	call changes#GetDiff(2)
com! ChangesDiffMode		call changes#GetDiff(3)

if s:autocmd
    call changes#Init()
endif
" =====================================================================
" Restoration And Modelines: {{{1
" vim: fdm=marker
let &cpo= s:keepcpo
unlet s:keepcpo

" Modeline
" vi:fdm=marker fdl=0
