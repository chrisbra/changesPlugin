" Changes.vim - Using Signs for indicating changed lines
" ------------------------------------------------------
" Version:  0.16
" Author:  Christian Brabandt <cb@256bit.org>
" Last Change: Thu, 15 Jan 2015 21:16:40 +0100
" License: Vim License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 15 :AutoInstall: ChangesPlugin.vim
" Documentation: "{{{1
" TODO: Remove old in-efficient sign handling, once 8.2 or so is stable
" See :h ChangesPlugin.txt

"{{{1script-level variables
scriptencoding utf-8
let s:i_path = fnamemodify(expand("<sfile>"), ':p:h'). '/changes_icons/'
let s:sign_api = v:version > 801 || (v:version == 801 && has("patch614"))
let s:sign_api_list = exists("*sign_placelist")
let s:sign_api_group = 'ChangesSignGroup'

fu! <sid>GetSID() "{{{1
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

    let s:ids={}
    let s:ids["add"]   = hlID("DiffAdd")
    let s:ids["del"]   = hlID("DiffDelete")
    let s:ids["cha"]   = hlID("DiffChange")
    let s:ids["ch2"]   = hlID("DiffText")

    call s:SetupSignTextHl()
    call s:DefineSigns(0)
endfu
fu! s:GetSignDef(def) "{{{1
    " Returns sign definition as string for use as `:sign command`
    " not used when s:sign_api is defined
    return (has_key(a:def, 'text') ? ' text='.get(a:def, 'text', '') : '').
        \ (has_key(a:def, 'texthl') ? ' texthl='.get(a:def, 'texthl', '') : '').
        \ (has_key(a:def, 'icon') ? ' icon='.get(a:def, 'icon', '') : '').
        \ (has_key(a:def, 'linehl') ? ' linehl='.get(a:def, 'linehl', '') : '')
endfu
fu! s:DefineSigns(undef) "{{{1
    if s:sign_api_list
        if a:undef
            call sign_undefine(keys(s:signs))
        endif
        call sign_define(values(s:signs))
        return
    endif
    for key in keys(s:signs)
        if a:undef
            try
                " Try undefining first, so that refining will actually work!
                if s:sign_api
                    call sign_undefine(s:signs[key].name)
                else
                    exe "sil! sign undefine " key
                endif
            catch /^Vim\%((\a\+)\)\=:E155/	" sign does not exist
            endtry
        endif
        try
            if s:sign_api
                call sign_define(key, s:signs[key])
            else
                exe "sil! sign define" key. s:GetSignDef(s:signs[key])
            endif
        catch /^Vim\%((\a\+)\)\=:E255/	" Can't read icons
            if s:sign_api
                call sign_undefine(key)
                unlet! s:signs[key]['icon']
                call sign_define(key, s:signs[key])
            else
                exe "sil! sign undefine " key
                unlet! s:signs[key]['icon']
                exe "sign define" key s:GetSignDef(s:signs[key])
            endif
        endtry
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
        elseif ((id == s:ids['cha']) || (id == s:ids['ch2']))  && a:arg
            let b:diffhl['cha']  = b:diffhl['cha'] + [ line ]
        endif
        let line+=1
    endw
endfu
fu! s:UpdateView(...) "{{{1
    " if a:1 is given, force update!
    let force = a:0
    let did_source_init = 0
    let b:changes_chg_tick = get(b:, 'changes_chg_tick', 0)
    try
        call changes#Init()
    catch
        call changes#CleanUp()
        return
    endtry
    let did_source_init = 1
    if !s:IsUpdateAllowed(1)
        return
    endif
    let b:changes_last_line = get(b:, 'changes_last_line', line('$'))
    if get(g:, 'gitgutter_enabled', 0) &&
                \ exists('b:gitgutter_gitgutter_signs')
        " Gitgutter plugin is available, stop here
        call changes#IgnoreCurrentBuffer()
        let force = 0
    endif
    " Only update, if there have been changes to the buffer
    if exists("b:diffhl") &&
                \ get(g:, 'changes_fast', 1) &&
                \ line("'[") == line("']") &&
                \ !empty(b:diffhl) &&
                \ index(b:diffhl['add'] + b:diffhl['cha'] + b:diffhl['del'], line("'[")) > -1 &&
                \ b:changes_last_line == line('$')
        " there already is a sign on the current line, so
        " skip an expensive call to create diff (might happen with many
        " rx commands on the same line and triggered TextChanged autocomands)
        " and should make Vim more responsive (at the cost of being a little
        " bit more unprecise.)
        " If you don't like this, set the g:changes_fast variable to zero
        let b:changes_chg_tick = b:changedtick
    endif

    if  b:changes_chg_tick != b:changedtick || force
        try
            if !did_source_init
                call changes#Init()
            endif
            call s:GetDiff(1, '')
            call s:HighlightTextChanges()
            let b:changes_chg_tick = b:changedtick
            let b:changes_last_line = line('$')
        catch
            call s:StoreMessage(v:exception)
            " Make sure, the message is actually displayed!
            verbose call changes#WarningMsg()
            call changes#CleanUp()
        endtry
    else
        " if nothing has been added, remove the sign, that has been added
        " using the InsertEnter autocommand
        if exists("s:changes_last_inserted_sign")
            let name=s:PrevDictHasKey(line('.'))
            if get(name, 'name', '') ==# s:changes_last_inserted_sign.name
                call s:UnPlaceSpecificSigns([{'id': get(name, 'id', s:SignIdRemove())}])
            endif
        endif
    endif
endfu
fu! s:SetupSignTextHl() "{{{1
    if &bg == 'dark'
        hi default ChangesSignTextAdd ctermbg=NONE ctermfg=darkgreen guibg=NONE guifg=darkgreen
        hi default ChangesSignTextDel ctermbg=NONE ctermfg=darkred guibg=NONE guifg=darkred
        hi default ChangesSignTextCh  ctermbg=NONE ctermfg=lightblue guibg=NONE guifg=lightblue
    else
        hi default ChangesSignTextAdd ctermbg=NONE ctermfg=green guibg=NONE guifg=green
        hi default ChangesSignTextDel ctermbg=NONE ctermfg=red guibg=NONE guifg=red
        hi default ChangesSignTextCh  ctermbg=NONE ctermfg=darkblue guibg=NONE guifg=darkblue
    endif
    hi default link ChangesSignTextDummyCh ChangesSignTextCh
    hi default link ChangesSignTextDummyAdd ChangesSignTextAdd
endfu
fu! s:ChangesSignsLines() "{{{1
    " returns a list of all changes placed signs
    return sort(map(copy(s:placed_signs[0]), 'get(v:val, "line")+0'), 'N')
endfu
fu! s:PrevDictHasKey(line) "{{{1
    " Return existing sign on the current line
    if s:sign_api
        let result=sign_getplaced(bufnr(''), {'group': s:sign_api_group, 'lnum': a:line})[0]['signs']
        return len(result) ? result[0] : {}
    endif
    let result=filter(copy(s:placed_signs[0]), 'v:val.line==?a:line')
    return result == [] ? {} : result[0]
endfu
fu! s:PrevDictHasKeyType(line, id) "{{{1
    " Return existing sign on the current line
    " If a:1, return complete dict item
    let result=filter(copy(s:placed_signs[0]), 'v:val.line ==? a:line && v:val.name[0:2] ==? a:id')
    return result == [] ? '' : result[0].name
endfu
fu! s:Write(name) "{{{1
    " turn off fsync, so writing is faster
    let _fsync=&fsync
    set nofsync
    exe ":sil keepalt noa :w!" a:name
    let &fsync=_fsync
endfu
fu! s:PlaceSigns(dict) "{{{1
    " signs by other plugins
    let b = copy(s:placed_signs[1])
    let changes_signs_lines=s:ChangesSignsLines()
    for id in ['add', 'cha', 'del']
        let prev_line = -1
        if !has_key(a:dict, id)
            " safety check
            break
        endif
        for item in a:dict[id]
            " One special case could occur:
            " You could delete the last lines. In that case, we couldn't place
            " here the deletion marks. If this happens, place the deletion
            " marks on the last line
            if item > line('$')
                let item=line('$')
            endif
            " There already exists a sign in this line, skip now
            if index(b, item) > -1
                continue
            endif
            let name=id
            " check if there is already a changes sign on the current line
            let sign_exists = index(changes_signs_lines, item) > -1
            let sign_exists_prev = index(changes_signs_lines, (item-1)) > -1
            " Make sure, 'dummych' ==? 'ch'
            " or 'dummydel' ==? 'del'
            if prev_line+1 == item || (sign_exists_prev && s:SignType(s:PrevDictHasKeyType(item-1, id)) ==? id)
                if id=='del'
                    " don't need to place more deleted signs on those lines,
                    " skip
                    let prev_line = item
                    continue
                else
                    let name=id.'_dummy'
                endif
            endif
            if sign_exists && get(s:PrevDictHasKey(item), 'name', '') ==? name
                " There is already a Changes sign placed
                continue
            endif
            let sid=b:sign_prefix.s:SignId()
            call s:PlaceSpecificSign(sid, item, name, bufnr(''))
            " remember line number, so that we don't place a second sign
            " there!
            call add(s:placed_signs[0], {'id': sid, 'line':item, 'type': name})
            let prev_line = item
        endfor
    endfor
endfu
fu! s:UnPlaceSigns(force) "{{{1
    if !exists("b:sign_prefix")
        return
    endif
    if a:force
        " only changes sign present, can remove all of them now
        if s:sign_api
            call sign_unplace(s:sign_api_group, {'buffer': bufnr('')})
        else
            exe "sign unplace * buffer=".bufnr('')
        endif
        return
    endif
    if !exists("b:diffhl")
        return
    endif
    let s:placed_signs = s:PlacedSigns()
    call s:UnPlaceSpecificSigns(s:placed_signs[0])
endfu
fu! s:StoreMessage(msg) "{{{1
    call add(s:msg, a:msg)
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
fu! s:ChangeDir() "{{{1
    let _pwd = fnameescape(getcwd())
    exe "lcd " fnameescape(fnamemodify(expand("%"), ':h'))
    return _pwd
endfu
fu! s:Output(list) "{{{1
    let eol="\n"
    if &ff ==? 'dos'
        let eol = "\r\n"
    elseif &ff ==? 'mac'
        let eol = "\n\r"
    endif
    return join(a:list, eol).eol
endfu
fu! s:DeleteTempFiles() "{{{1
    for file in glob(s:diff_out.'*', 1, 1)
        call delete(file)
    endfor
endfu
fu! s:MakeDiff_new(file, type) "{{{1
    " Parse Diff output and place signs
    " Needs unified diff output
    let outfile = printf("%s.%d", s:diff_out, s:jobid)
    try
        let _pwd = s:ChangeDir()
        unlet! b:current_line
        call s:Write(s:diff_in_cur)
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
        let cmd = printf("diff -a -U0 -N %s %s %s > %s",
            \ s:diff_in_old, s:diff_in_cur, 
            \ (get(g:, 'changes_grep_diff', 0) ? '|fgrep "@@"' : ''),
            \ outfile)
        if s:Is('win') && &shell =~? 'cmd.exe$'
            let cmd = '( '. cmd. ' )'
        endif
        if has('job')
            call s:ChangesDoAsync(cmd, fnamemodify(bufname(''), ':p'), a:type, outfile)
        else
            let output = system(cmd)
            if v:shell_error >= 2 || v:shell_error < 0
                " diff returns 2 on errors
                call s:StoreMessage(output[:-2])
                throw "changes:abort"
            endif
            if getfsize(outfile) <= 0
                call s:StoreMessage("File not found or no differences found!")
                return
            endif
            call s:ParseDiffOutput(outfile)
        endif
    finally
        if filereadable(outfile)
            call s:PreviewDiff(outfile)
        endif
        exe 'lcd' _pwd
    endtry
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
        exe ":silent :noa :r " (exists("a:1") && !empty(a:1) ? a:1 : '#')
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
                call s:StoreMessage("Couldn't get VCS output, aborting")
                "call s:MoveToPrevWindow()
                exe "noa" bufwinnr(bnr) "wincmd w"
                throw "changes:abort"
            endif
            exe ':silent :noa :r' s:diff_out
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
    let file=readfile(a:file)
    if !get(g:, 'changes_grep_diff', 0)
        let file=filter(file, 'v:val=~''^@@''')
    endif
    for line in file
        " TODO: matchlist seems slow, can this be made faster by manually parsing?
        let submatch = matchlist(line, '@@ -\(\d\+\),\?\(\d*\) +\(\d\+\),\?\(\d*\) @@')
        if empty(submatch)
            " There was probably an error, skip parsing now
            return
        else
            let old_line = submatch[1] + 0
            let old_count = (empty(submatch[2]) ? 1 : submatch[2] + 0)
            let new_line = submatch[3] + 0
            let new_count = (empty(submatch[4]) ? 1 : submatch[4] + 0)
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
        "
        " But this is just a Change:
        " @@ -1010,5 +1020,5 @@
        elseif old_count >= new_count
            let b:diffhl.cha += range(new_line, new_line + new_count - 1)
            " if old and new count is not given, can't be deletion
            " I think this is wrong:
            " if new_line + new_count < old_line+old_count && !(empty(submatch[2]) && empty(submatch[4]))
            " should probably rather be:
            if new_line + new_count < old_line + old_count && new_count != old_count
                let b:diffhl.del+= range(new_count + new_line, old_line + old_count - 1)
            endif

        " Lines changed
        " 3 added, 2 changed
        " @@ -4,2 +4,5 @@
        else " old_count < new_count
            let b:diffhl.cha += range(new_line, new_line + old_count - 1)
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
endfu
fu! s:ShowDifferentLines() "{{{1
    if !exists("b:diffhl")
        return
    else
        let list=[]
        let placed={}
        let tline = -1
        let types={'cha':'*', 'add': '+', 'del': '-'}
        for type in ['cha', 'del', 'add']
            for line in b:diffhl[type]
                if has_key(placed, line)
                    continue
                endif
                if line == tline+1
                    let tline=line
                    continue
                endif
                call add(list, {'bufnr': bufnr(''),
                            \ 'lnum': line, 'text': getline(line),
                            \ 'type': types[type]})
                let placed.line=1
                let tline=line
            endfor
        endfor
    endif
    if !empty(list)
        call setloclist(winnr(), list)
        lopen
    endif
endfun
let g:Changes_funcref=funcref("<sid>ShowDifferentLines")
fu! s:GetSignId() "{{{1
    " Not called for s:sign_api
    let signs = s:GetPlacedSigns()
    if empty(signs)
        " No signs placed yet...
        return 10
    endif
    let list=[]
    for val in signs[1:]
        " get 'id' value of signs
        let id = split(val, '=\d\+\zs')[1]
        call add(list, (split(id, '=')[1] + 0))
    endfor
    return max(list)
endfu
fu! s:GetPlacedSigns() "{{{1
    if s:sign_api
        return sign_getplaced(bufnr(''), {'group': s:sign_api_group})
    elseif exists("s:all_signs")
        return s:all_signs
    else
        " set local to english
        let lang=v:lang
        if lang isnot# 'C'
            sil lang mess C
        endif
        redir => a| exe "silent sign place buffer=".bufnr('')|redir end
        let s:all_signs = split(a,"\n")[1:]
        if lang != 'C'
            exe "sil lang mess" lang
        endif
    endif
    return s:all_signs
endfu
fu! s:PlacedSigns() "{{{1
    if empty(bufname(''))
        " empty(bufname): unnamed buffer, can't get diff of it,
        " anyhow, so stop expansive call here
        return [[],[]]
    endif
    let b = s:GetPlacedSigns()
    if s:sign_api
        return [[], b]
    endif
    if empty(b)
        return [[],[]]
    endif
    let dict  = {}
    let own   = []
    let other = []
    " Filter from the second item. The first one contains the buffer name:
    " Signs for [NULL]: or  Signs for <buffername>:
    let b=b[1:]
    let c=filter(copy(b), 'v:val =~ "id=".b:sign_prefix')
    for item in b
        if item =~ "id=".b:sign_prefix
            " Signs placed by this plugin
            let t = split(item)
            let dict.line = split(t[0], '=')[1]
            let dict.id   = split(t[1], '=')[1]
            let dict.name = split(t[2], '=')[1]
            call add(own, copy(dict))
        else
            call add(other, matchstr(item, '^\s*\w\+=\zs\d\+\ze')+0)
        endif
    endfor

    " Make sure s:GetPlacedSigns() reruns correctly
    unlet! s:all_signs
    return [own, other]
endfu
fu! s:GuessVCSSystem() "{{{1
    " Check global config variable
    for var in [ b:, g:]
        let pat='\c\vgit|hg|bzr\|cvs|svn|subversion|mercurial|rcs|fossil|darcs'
        let vcs=matchstr(get(var, 'changes_vcs_system', ''), pat)
        if vcs
            return vcs
        endif
    endfor
    let file = fnamemodify(resolve(expand("%")), ':p')
    let path = escape(fnamemodify(file, ':h'), ' ')
    " First try git and hg, they seem to be the most popular ones these days
    " also check that the file actually exists in the repository
    if !empty(finddir('.git',path.';')) &&
        \ !empty(system('git ls-tree -r HEAD --name-only '. file))
        return 'git'
    elseif !empty(finddir('.hg',path.';')) &&
        \ empty(system('hg status -ui '. file))
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
    let lines = a:fwd ? a:list : reverse(a:list)
    for item in lines
        if  (a:fwd && temp == item - 1) || (!a:fwd && temp == item + 1)
            call remove(lines, index(lines, item))
        endif
        let temp = item
    endfor
    return lines
endfu
fu! s:GetDiff(arg, file) "{{{1
    " a:arg == 1 Create signs
    " a:arg == 2 Show changed lines in locationlist
    " a:arg == 3 Stay in diff mode
    " a:file -> which file to diff against

    " If error happened, don't try to get a diff list
    try
        if changes#CurrentBufferIsIgnored() ||
                    \ !empty(&l:bt) || line2byte(line('$')) == -1
            call s:StoreMessage('Buffer is ignored')
            return
        endif

        " Save some settings
        let _wsv   = winsaveview()
        " Lazy redraw
        setl lz
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

            " do not generate signs for special buffers
            if !empty(&buftype)
                call s:StoreMessage("Not generating diff for special buffer!")
                call changes#IgnoreCurrentBuffer()
                return
            endif

            let b:diffhl={'add': [], 'del': [], 'cha': []}
            if a:arg == 3
                let s:temp = {'del': []}
                let curbuf = bufnr('%')
                let _ft = &ft
                let scratchbuf = s:MakeDiff(a:file)
                call s:CheckLines(1)
                exe "noa" bufwinnr(scratchbuf) "wincmd w"
                exe "setl ft=". _ft
                call s:CheckLines(0)
                " Switch to other buffer and check for deleted lines
                exe "noa" bufwinnr(curbuf) "wincmd w"
                let b:diffhl['del'] = s:temp['del']
            else
                " parse diff output
                call s:MakeDiff_new(a:file, a:arg)
            endif
            if !has("job")
                call s:AfterDiff(bufnr(''))
                if a:arg != 3 || s:nodiff
                    let b:changes_view_enabled=1
                endif
                if a:arg ==# 2
                    call s:ShowDifferentLines()
                endif
            endif
        catch /^Vim\%((\a\+)\)\=:E139/	" catch error E139
            return
        catch /^changes/
            let b:changes_view_enabled=0
            call changes#IgnoreCurrentBuffer()
        catch
            call s:StoreMessage("Error occured: ".v:exception)
            call s:StoreMessage("Trace: ". v:throwpoint)
        finally
            if s:vcs && get(b:, "b:changes_view_enabled", 0)
                " only add info here, when 'verbose' > 1
                call s:StoreMessage("Check against ".
                    \ fnamemodify(expand("%"),':t') . " from " . b:vcs_type)
            endif
            " redraw (there seems to be some junk left)
            " disabled, redraw is expensive
            "redr!
        endtry
    finally
        if exists("_wsv")
            call winrestview(_wsv)
        endif
        " Make sure, the message is actually displayed!
        call changes#WarningMsg()
        " restore change marks
        call s:SaveRestoreChangeMarks(0)
    endtry
endfu
fu! s:AfterDiffAPI(bufnr) "{{{1
    " Get all currently placed signs in the buffer
    let placed_signs = sign_getplaced(a:bufnr, {'group': s:sign_api_group})
    if len(placed_signs[0]['signs']) > 0
        " remove signs, that are no longer needed anymore
        let newly_signs = b:diffhl['add'] + b:diffhl['cha'] + b:diffhl['del']
        let to_remove = filter(placed_signs[0]['signs'], { idx, val -> index(newly_signs, val.lnum) == -1})
        call map(to_remove, {idx, val -> sign_unplace(s:sign_api_group, {'id': val.id})}) 
    endif
    for name in ['del', 'add', 'cha']
        " Del delete first, since those refer to the old line numbers
        let previous=-1
        let id = 0
        for line in b:diffhl[name]
            let actual_name = name
            let cur_sign = sign_getplaced(a:bufnr, {'group': s:sign_api_group, 'lnum':line})
            let length=len(cur_sign[0]['signs'])
            let cur_id = 0
            let cur_name = ''
            while length > 0
                " In case there are several signs on the current line,
                " remove all except for the last one
                let cur_id = cur_sign[0]['signs'][length-1]['id']
                let cur_name = cur_sign[0]['signs'][length-1]['name']
                if length > 1
                    call sign_unplace(s:sign_api_group, {'id':cur_id})
                endif
                let length -= 1
            endwhile
            if line==previous+1
                " There was a sign on the previous line
                if index(['add', 'cha'], name) > -1
                    let actual_name = name.'_dummy'
                    " Only place sign, if the old existing sign is not of the
                    " same type (name)
                    if actual_name isnot# cur_name
                        call s:PlaceSpecificSign(cur_id, line, actual_name, a:bufnr)
                    endif
                else
                    " nothing to do for deleted lines,
                    " but remove previously placed lines
                    if cur_id > 0
                        call sign_unplace(s:sign_api_group, {'id': cur_id})
                    endif
                    let previous=line
                    continue
                endif
            else
                " Only place sign, if the old existing sign is not of the same type (name)
                if actual_name isnot# cur_name
                    call s:PlaceSpecificSign(cur_id, line, actual_name, a:bufnr)
                endif
            endif
            let previous=line
        endfor
    endfor
endfu
fu! s:AfterDiff(bufnr) "{{{1
    call s:SortDiffHl()
    if s:sign_api
        call s:AfterDiffAPI(a:bufnr)
        return
    endif
    " Check for empty dict of signs
    if !exists("b:diffhl") ||
                \ ((b:diffhl ==? {'add': [], 'del': [], 'cha': []})
                \ && empty(s:placed_signs[0]))
        " Make sure, diff and previous diff are different,
        " otherwise, we might forget to update the signs
        call s:StoreMessage('No differences found!')
        let s:nodiff=1
    else
        let s:diffhl = s:CheckInvalidSigns()
        " remove invalid signs
        " s:diffhl[0] - invalid signs, that need to be removed
        " s:diffhl[1] - valid signs, that need to be added
        " safety check
        if type(s:diffhl) == type([]) && len(s:diffhl) == 2 && type(s:diffhl[0]) == type([])
            call s:UnPlaceSpecificSigns(s:diffhl[0])
            call s:PlaceSigns(s:diffhl[1])
        endif
    endif
endfu
fu! s:SortDiffHl() "{{{1
    for i in ['add', 'cha', 'del']
        call sort(b:diffhl[i], 'N')
        call uniq(b:diffhl[i])
    endfor
endfu
fu! s:SignType(string) "{{{1
    " returns type but skips dummy type
    return a:string[0:2]
    "return matchstr(a:string, '\(dummy\)\?\zs.*$')
endfu
fu! s:CheckInvalidSigns() "{{{1
    " list[0]: signs to remove
    " list[1]: signs to add
    let list=[[],{'add': [], 'del': [], 'cha': []}]
    let ind=0
    let last={}
    try
        " 1) check, if there are signs to delete
        for item in s:placed_signs[0]
            if (item.name ==? '[Deleted]')
                call add(list[0], item)
                continue
            elseif (item.line == get(last, 'line', 0))
                " remove duplicate signs
                call add(list[0], item)
                continue
            endif
            let type=s:SignType(item.name)
            if match(keys(b:diffhl), type) < 0
                continue
            endif
            if !empty(type) && index(b:diffhl[type], item.line+0) == -1
                call add(list[0], item)
                " remove item from the placed sign list, so that we
                " don't erroneously place a dummy sign later on
                let next = get(s:placed_signs[0], ind+1, {})
                if item.name !~? 'dummy' && !empty(next) && next.name =~? 'dummy'
                    " The next line should not be of type dummy, so add it to the
                    " delete list and to the add list
                    call add(list[0], next)
                    if index(b:diffhl[type], next.line+0) > -1
                        call add(list[1][type], next.line+0)
                    endif
                    call remove(s:placed_signs[0], ind+1)
                endif
                call remove(s:placed_signs[0], ind)
            else
                if item.name =~? 'dummy' && s:SignType(get(last, 'name', '')) != type
                    call add(list[0], item)
                    if index(b:diffhl[type], item.line+0) > -1
                        call add(list[1][type],  item.line+0)
                    endif
                endif
                if s:SignType(item.name) == s:SignType(get(last, 'name', ''))
                            \ && item.name !~ 'dummy'
                            \ && item.line+0 == get(last, 'line', 0)+1
                    " Current type needs to be of type dummy, but isn't,
                    " remove and re-add the sign
                    call add(list[0], item)
                    call add(list[1][type],  item.line+0)
                endif
                let ind+=1
                let last = item
            endif
        endfor
        " Check, which signs are to be placed
        let changes_signs_lines=s:ChangesSignsLines()
        for id in ['add', 'cha', 'del']
            for line in b:diffhl[id]
                let has_sign = index(changes_signs_lines, line) > -1
                let cur  = index(list[1][id], line)
                let prev = index(b:diffhl[id], (line-1))
                if !has_sign && cur == -1
                    call add(list[1][id], line)
                elseif prev > -1 && index(list[1][id],  (line-1)) > -1
                    " if a new line is inserted above an already existing line
                    " with sign type 'add' make sure, that the already existing
                    " sign type 'add' will be set to 'dummyadd' so that the '+'
                    " sign appears at the correct line
                    if cur == -1
                        call add(list[1][id], line)
                    endif
                    if has_sign
                        let previtem = s:PrevDictHasKey(line)
                        if previtem.name == id
                            call add(list[0], previtem)
                        endif
                    endif
                endif
            endfor
        endfor
    catch
    finally
        " in any case, return an empty list
        return list
    endtry
endfu
fu! s:UnPlaceSpecificSigns(dict) "{{{1
    for sign in a:dict
        let ind = index(s:placed_signs[0], sign)
        if ind > -1
            call remove(s:placed_signs[0], ind)
        endif
        if s:sign_api
            call sign_unplace(s:sign_api_group, {'id': sign.id, 'buffer': bufnr('')})
        else
            exe "sign unplace ". sign.id. " buffer=".bufnr('')
        endif
    endfor
endfu
fu! s:PlaceSpecificSign(id, line, type, bufnr) "{{{1
    if s:sign_api
        call sign_place(a:id, s:sign_api_group, a:type, a:bufnr, {'lnum': a:line})
    else
        exe printf("sil sign place %d line=%d name=%s buffer=%d",
                \ a:id, a:line, a:type, a:bufnr)
    endif
endfu
fu! s:InitSignDef() "{{{1
    let signs={}
    let s:changes_sign_hi_style = get(s:, 'changes_sign_hi_style', 0)
    let sign_hi = s:changes_sign_hi_style
    if sign_hi == 2
        for name in ['add', 'del', 'ch']
            let signs.name = {'text': "\<Char-0xa0>", 'texthl': 'SignColumn'}
        endfor
    else
        let plus = (get(g:, 'changes_sign_text_utf8', 0) ? '➕' : '+')
        let del  = (get(g:, 'changes_sign_text_utf8', 0) ? '➖' : '-')
        let mod  = (get(g:, 'changes_sign_text_utf8', 0) ? '★' : '*')

        let signs['add'] = {
                    \ 'text': plus,
                    \ 'texthl': (sign_hi<2 ? "ChangesSignTextAdd" : "SignColumn"),
                    \ 'icon': s:MakeSignIcon(s:i_path.'add1.bmp'),
                    \ 'linehl': sign_hi > 0 ? 'DiffAdd' : ''}
        let signs['del'] = {
                    \ 'text': del,
                    \ 'texthl': (sign_hi<2 ? "ChangesSignTextDel" : "SignColumn"),
                    \ 'icon': s:MakeSignIcon(s:i_path.'delete1.bmp'),
                    \ 'linehl': sign_hi > 0 ? 'DiffDelete' : ''}
        let signs['cha'] = {
                    \ 'text': mod,
                    \ 'texthl': (sign_hi<2 ? "ChangesSignTextCh" : "SignColumn"),
                    \ 'icon': s:MakeSignIcon(s:i_path.'warning1.bmp'),
                    \ 'linehl': sign_hi > 0 ? 'DiffChange' : ''}
    endif
    let signs['add_dummy'] = {
                    \ 'text': plus,
                    \ 'texthl': (sign_hi<2 ? "ChangesSignTextDummyAdd": "SignColumn"),
                    \ 'linehl': sign_hi > 0 ? 'DiffAdd' : ''}
    let signs['cha_dummy'] = {
                    \ 'text': mod,
                    \ 'texthl': (sign_hi<2 ? "ChangesSignTextDummyCh": "SignColumn"),
                    \ 'linehl': sign_hi > 0 ? 'DiffChange' : ''}

    for name in keys(signs)
      " remove empty keys from dictionary
      call filter(signs[name], {key, val -> !empty(val)})
      " add name of sign to the definition, required for sign_define([list])
      let signs[name].name = name
    endfor

    return signs
endfu
fu! s:MakeSignIcon(path) "{{{1
    " Windows seems to have problems with the gui
    if has("gui_running") && !s:Is("win") &&
        \ get(g:, 'changes_use_icons', 1) &&
        \ filereadable(a:path)
        return a:path
    else
        return ''
    endif
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
fu! s:SignIdRemove() "{{{1
    if !exists("b:changes_sign_id")
        return
    endif
    " return the last id, that has been used for placing a sign
    " and decrement id, so that the next call to s:SignId() will
    " get a valid ID
    let b:changes_sign_id -= 1
    return printf("%d%02d", b:sign_prefix, b:changes_sign_id + 1)
endfu
fu! s:SignId() "{{{1
    let b:changes_sign_id = get(b:, 'changes_sign_id', 0) + 1
    return b:changes_sign_id
endfu
fu! s:IsUpdateAllowed(empty) "{{{1
    if !empty(&buftype) || &ro || &diff || changes#CurrentBufferIsIgnored()
        " Don't make a diff out of an unnamed buffer
        " or of a special buffer or of a read-only buffer
        if !empty(&buftype)
            call s:StoreMessage("Special Buffer, not performing diffs!")
        elseif &ro
            call s:StoreMessage("Buffer read-only, not performing diffs!")
        elseif &diff
            call s:StoreMessage("disabled for diff-mode!")
        else
            call s:StoreMessage("Buffer is currently ignored, not performing diffs!")
        endif
        return 0
        " only check for empty buffer when a:empty is true
    elseif a:empty && empty(bufname(''))
        call s:StoreMessage("Buffer hasn't been written yet. Can't diff!")
        return 0
    elseif !empty(bufname('')) && ((get(g:, 'changes_max_filesize', 0) > 0 &&
            \ g:changes_max_filesize < getfsize(bufname(''))) ||
            \ getfsize(bufname('')) < 0)
        call s:StoreMessage('FileSize too large, skipping check')
        return 0
    endif
    return 1
endfu

if has("job") "{{{1
    let s:jobs = {}

    function! s:on_exit(channel) dict abort "{{{2
        if getfsize(self.output) <= 0
            call s:StoreMessage("File not found or no differences found!")
            if exists("b:diffhl")
                " might need to remove invalid signs
                call s:AfterDiff(self.bufnr)
            endif
            call changes#WarningMsg()
            return
        endif
        if !exists("b:diffhl")
            let b:diffhl={'add': [], 'del': [], 'cha': []}
        endif
        call s:ParseDiffOutput(self.output)
        call s:AfterDiff(self.bufnr)
        " redrawing is expansive, skipped
        "redr!
        if self.type != 3 || s:nodiff
            let b:changes_view_enabled=1
        endif
        if self.type ==# 2
            call s:ShowDifferentLines()
        endif
        call changes#WarningMsg()
        call s:SaveRestoreChangeMarks(0)
        " Remove from s:jobs
        if has_key(s:jobs, self.file)
            call remove(s:jobs, self.file)
        endif
        let s:jobid -= 1
    endfunction

    function! s:ChangesDoAsync(cmd, file, type, outfile) "{{{2
        if s:Is("win")
            let cmd = (&sh =~# 'cmd.exe' ? 'cmd.exe /c ' : 'sh -c ') . a:cmd
        else
            let cmd = ['sh', '-c', a:cmd]
        endif
        if !empty(a:outfile)
            let outfile=s:diff_out.'.'.s:jobid
        else
            let outfile=a:outfile
        endif
        if empty(a:file)
            return
        endif

        let options = {'file': a:file, 'cmd': a:cmd, 'type': a:type, 'output': outfile, 'bufnr': bufnr('')}
        if has_key(s:jobs, a:file)
            if job_status(get(s:jobs, a:file)) == 'run'
                return
            else
                call job_stop(get(s:jobs, a:file))
                call remove(s:jobs, a:file)
                if s:jobid > 1
                    let s:jobid -= 1
                endif
            endif
        endif
        let id = job_start(cmd, {
            \ 'err_io':   'out',
            \ 'close_cb': function('s:on_exit', options)})
        let s:jobs[a:file] = id
        let s:jobid += 1
    endfu
endif

fu! changes#SetSignColumn() "{{{1
    if exists("s:old_signcolumn") && &scl isnot# 'yes'
        " user changed the setting, do not change it back again
        if &scl is# 'no'
            throw 'changes:abort'
        else
            return
        endif
    elseif &scl isnot# 'yes' && !&buftype ==# 'terminal'
        set signcolumn=yes
        let s:old_signcolumn = 1
    endif
endfu
fu! changes#GetStats() "{{{1
    return [  len(get(get(b:, 'diffhl', []), 'add', [])),
            \ len(get(get(b:, 'diffhl', []), 'cha',  [])),
            \ len(get(get(b:, 'diffhl', []), 'del', []))]
endfu
fu! changes#WarningMsg() "{{{1
    if !&vbs
        " Set verbose to 1 to have messages displayed!
        return
    endif
    if !empty(s:msg)
        redraw!
        let msg=["Changes.vim: " . s:msg[0]] + (len(s:msg) > 1 ? s:msg[1:] : [])
        echohl WarningMsg
        for mess in reverse(msg)
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
        let ch  = matchstr(sign_def['cha'], 'text=\zs..')
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
    if !exists("s:ignore")
        let s:ignore   = {}
    endif
    let s:changes_signs_undefined=0
    let s:autocmd  = get(g:, 'changes_autocmd', 1)
    " Check against a file in a vcs system
    let s:vcs      = get(g:, 'changes_vcs_check', 0)
    if !exists("b:vcs_type")
        if exists("g:changes_vcs_system")
            let b:vcs_type = g:changes_vcs_system
        endif
        if exists("b:changes_vcs_system")
            let b:vcs_type = b:changes_vcs_system
        endif
        if !exists("b:vcs_type")
            let b:vcs_type = s:GuessVCSSystem()
        endif
    endif
    if s:vcs && empty(b:vcs_type)
        " disable VCS checking...
        let s:vcs=0
    endif
    if !exists("s:vcs_cat")
        let s:vcs_cat  = {'git': 'show :',
                    \'bzr': 'cat ',
                    \'cvs': '-q update -p ',
                    \'darcs': '--show-contents ',
                    \'fossil': 'finfo -p ',
                    \'rcs': 'co -p ',
                    \'svn': 'cat ',
                    \'hg': 'cat '}

        " Define aliases...
        let s:vcs_cat.mercurial  = s:vcs_cat.hg
        let s:vcs_cat.subversion = s:vcs_cat.svn
        let s:vcs_diff = {'git': ' diff -U0 --no-ext-diff --no-color ',
                    \ 'hg' : ' diff -U0 '}
        let s:vcs_apply = {'git': ' apply --cached --unidiff-zero ',
                    \ 'hg' :  ' import - '}
    endif

    " Settings for Version Control
    if s:vcs && !empty(b:vcs_type)
        if get(s:vcs_cat, b:vcs_type, 'NONE') == 'NONE'
            call s:StoreMessage("Don't know VCS " . b:vcs_type)
            call s:StoreMessage("VCS check will be disabled for now.")
            let s:vcs=0
            " Probably file not in a repository/working dir
        endif
        if !executable(b:vcs_type)
            call s:StoreMessage("Guessing VCS: ". b:vcs_type)
            call s:StoreMessage("Executable " . b:vcs_type . " not found! Aborting.")
            call s:StoreMessage("You might want to set the g:changes_vcs_system variable to override!")
            let s:vcs=0
            " Probably file not in a repository/working dir
        endif
    endif
    if !exists("s:diff_out")
        let s:diff_out    = tempname()
        let s:diff_in_cur = s:diff_out.'.cur.txt'
        let s:diff_in_old = s:diff_out.'.old.txt'
        let s:jobid = 1  " job id
    endif
    let s:nodiff=0
    " Make sure, we are fetching all placed signs again
    unlet! s:all_signs
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
            let s:autocmd = 0
            throw "changes:abort"
            return
        endtry
        let s:precheck=1
    endif
    if !get(g:, 'changes_respect_SignColumn', 0)
        " Make the Sign column not standout
        hi! clear SignColumn
        if &l:nu || &l:rnu
            hi! link SignColumn LineNr
        else
            hi! link SignColumn Normal
        endif
    endif
    " This variable is a prefix for all placed signs.
    " This is needed, to not mess with signs placed by the user
    if !exists("b:sign_prefix")
        let b:sign_prefix = (s:sign_api ? '' : s:GetSignId() + 10)
    endif

    let s:placed_signs = s:PlacedSigns()
    if s:old_signs !=? s:signs && !empty(s:old_signs)
        " Sign definition changed, redefine them
        call s:UnPlaceSpecificSigns(s:placed_signs[0])
        call s:DefineSigns(1)
        " need to parse placed signs again...
        let s:placed_signs = s:PlacedSigns()
    endif
    call changes#SetSignColumn()
    call changes#AuCmd(s:autocmd)
    " map <cr> to update sign column, if g:changes_fast == 0
    if !hasmapto('<cr>', 'i') && !get(g:, 'changes_fast', 1)
        call ChangesMap('<cr>')
    endif
endfu
fu! changes#CurrentBufferIsIgnored() "{{{1
    return exists("s:ignore") && get(s:ignore, bufnr('%'), 0)
endfu
fu! changes#IgnoreCurrentBuffer() "{{{1
    if !exists("s:ignore")
        let s:ignore = {}
    endif
    let s:ignore[bufnr('%')]=1
endfu
fu! changes#UnignoreCurrentBuffer() "{{{1
    if changes#CurrentBufferIsIgnored()
        call remove(s:ignore, bufnr('%'))
    endif
endfu
fu! changes#EnableChanges(arg, ...) "{{{1
    " if a:1 given, make a diff against the given file
    call changes#UnignoreCurrentBuffer()
    try
        let savevar = get(g:, 'changes_max_filesize', 0)
        unlet! g:changes_max_filesize
        call changes#Init()
        if a:arg
            call s:UnPlaceSigns(1)
        endif
        verbose call s:GetDiff(a:arg, (a:0 ? a:1 : ''))
    catch
        call changes#WarningMsg()
        call changes#CleanUp()
    finally
        if savevar > 0
            let g:changes_max_filesize = savevar
        endif
    endtry
endfu
fu! changes#CleanUp() "{{{1
    " only delete signs, that have been set by this plugin
    call s:UnPlaceSigns(1)
    call changes#IgnoreCurrentBuffer()
    for key in keys(get(s:, 'signs', {}))
        exe "sil! sign undefine " key
    endfor
    if s:autocmd
        call changes#AuCmd(0)
    endif
    let b:changes_view_enabled = 0
    if exists("b:changes_linehi_diff_match")
        for val in values(b:changes_linehi_diff_match)
            " ignore possible errors
            sil! call matchdelete(val)
        endfor
    endif
    unlet! b:diffhl s:signs s:old_signs b:changes_linehi_diff_match b:changes_sign_id s:precheck
endfu
fu! changes#AuCmd(arg) "{{{1
    if a:arg
        if !exists("#Changes")
            augroup Changes
                autocmd!
                au TextChanged,InsertLeave,FilterReadPost * :call s:UpdateView()
                " make sure, hightlighting groups are not cleared
                au ColorScheme,GUIEnter * :try|call s:Check() |catch|endtry
                if s:Is('unix')
                    " FocusGained does not work well on Windows
                    " because calling background processess triggers
                    " FocusGAined autocommands recursively
                    au FocusGained * :call s:UpdateView(1)
                endif
                if !get(g:, 'changes_fast', 1)
                    au InsertEnter * :call changes#InsertSignOnEnter()
                endif
                au BufWritePost,BufWinEnter * :call s:UpdateView(1)
                au VimLeave * call s:DeleteTempFiles()
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
    if  get(b:, "changes_view_enabled", 0)
        call s:UnPlaceSigns(0)
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
endfu
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
                \   get(dict, "cha",  [])
    let lines = sort(lines, 'n')
    " remove duplicates
    let lines = uniq(lines)
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
    let lines = sort(lines, 'n')

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
fu! changes#FoldDifferences(...) "{{{1
    if &fde!=?'index(g:lines,v:lnum)>-1?0:1'
        let b:chg_folds = {'fen': &fen, 'fdm': &fdm, 'fde': &fde}
        " Use context from 'diffopt' setting, if it is set
        let context = matchstr(&diffopt, 'context:\zs\d\+\ze')+0
        if context == 0
            let context = 3
        endif
        let context = empty(a:000) ? context : a:1
        let g:lines = []
        let dict=get(b:, 'diffhl', {})
        for line in sort(get(dict, 'add', []) + get(dict, 'cha' , []) + get(dict, 'del', []), 'n')
            for item in range(line-context,line+context)
                " Add some context
                if index(g:lines, item) > -1 || item < 1 || item > line('$')
                    continue
                endif
                call add(g:lines, item)
            endfor
        endfor
        let g:lines=uniq(g:lines)
        if !empty(g:lines)
            setl fen fdm=expr fde=index(g:lines,v:lnum)>-1?0:1
        else
            let s:msg=[]
            call s:StoreMessage('Not folding, no lines changes!')
            verbose call changes#WarningMsg()
        endif
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
fu! changes#MapCR() "{{{1
    if !( pumvisible() ||
                \ (exists("*wildmenumode") && wildmenumode()))
        call changes#InsertSignOnEnter()
    endif
    return ''
endfu
fu! changes#InsertSignOnEnter() "{{{1
    " prevent an expansive call to create a diff,
    " simply check, if the current line has a sign
    " and if not, add one
    unlet! s:changes_last_inserted_sign
    if !s:IsUpdateAllowed(1) || &cpo =~ '$'
        " If '$' is inside 'cpo' setting, than the redraw by placing a sign
        " will overwrite the '$' placed from the change command. So return
        " if the user has '$' inside the cpoptions.
        return
    endif
    try
        call changes#Init()
    catch changes:abort
    endtry
    let line = line('.')
    let prev = line - 1
    let next = line + 1
    let name=s:PrevDictHasKey(line)
    if name == {}
        " no sign yet on current line, add one.
        let prevname = s:PrevDictHasKey(prev)
        let name = ((get(prevname, 'name', '') =~? 'add') ? 'add_dummy' : 'add')
        let id=b:sign_prefix.s:SignId()
        call s:PlaceSpecificSign(id, line, name, bufnr(''))
        " on o in normal mode, we should keep the sign
        if get(b:, 'changes_last_line', 0) == line('$')
            let s:changes_last_inserted_sign={'id': id, 'line':line, 'type':name}
        endif
    endif
    if get(s:PrevDictHasKey(next),'name', '') ==? 'add'
        let item = filter(copy(s:placed_signs[0]), 'v:val.line ==? next')
        call s:UnPlaceSpecificSigns(item)
        call s:PlaceSpecificSign(item[0].id, next, 'add_dummy', bufnr(''))
    endif
    let b:changes_last_line = line('$')
endfu
fu! changes#StageHunk(line, revert) "{{{1
    try
        let cur = a:line
        let _pwd = s:ChangeDir()
        let _wsv = winsaveview()
        let _vbs = &verbose
        call changes#Init()
        if get(b:, 'vcs_type', '') !=? 'git'
            let &vbs=1
            call s:StoreMessage("Sorry, staging Hunks is only supported for git!")
            return
        elseif !a:revert && changes#GetStats() ==? [0,0,0]
            let &vbs=1
            call s:StoreMessage('No changes detected, nothing to do!')
            return
        endif
        if  changes#GetStats() !=? [0,0,0] || a:revert
            if &mod
                sil noa write
            endif
            let git_rep_p = s:ReturnGitRepPath()
            exe "lcd" git_rep_p
            " When reverting, need to get cached diff
            let diff = split(system(b:vcs_type.
                        \ s:vcs_diff[b:vcs_type].
                        \ (a:revert ? ' --cached ' : '').
                        \ expand('%')), "\n")
            if v:shell_error
                let &vbs=1
                call s:StoreMessage("Error occured: ". join(diff, "\n"))
                return
            endif
            let file=''
            let found=0
            let hunk=[]
            let index = match(diff, '^+++')
            for line in diff[index + 1 : ]
                if line =~? '^@@.*@@'
                    if found
                        break
                    endif
                    let temp = split(line)[2]
                    let lines = split(temp, ',')
                    call map(lines, 'matchstr(v:val, ''\d\+'')+0')
                    if (len(lines) == 2 &&
                                \ cur >= lines[0] && cur < lines[0]+lines[1]) ||
                                \ (len(lines) == 1 && cur == lines[0]) ||
                                \ (len(lines) == 2 && lines[1] == 0 && cur == lines[0])
                        " this is the hunk the cursor is on
                        let found=1
                    endif
                endif
                if found
                    call add(hunk, line)
                endif
            endfor
            if empty(hunk)
                call s:StoreMessage('Cursor not on a diff hunk, aborting!')
                let &vbs=1
                return
            endif
            " Add filename to hunk
            let hunk = diff[0:index] + hunk
            let output=system(b:vcs_type. s:vcs_apply[b:vcs_type].
                        \ (a:revert ? ' --reverse - ' : ' - '),
                        \ s:Output(hunk))
            if v:shell_error
                call s:StoreMessage(output)
            endif
            call s:GetDiff(1, '')
        endif
    catch
        let &vbs=1
        call s:StoreMessage("Exception occured")
        call s:StoreMessage(string(v:exception))
    finally
        exe "lcd " _pwd
        call changes#WarningMsg()
        if &vbs != _vbs
            let &vbs = _vbs
        endif
        call winrestview(_wsv)
    endtry
endfu
" Modeline "{{{1
" vi:fdm=marker fdl=0 ts=4 sw=4 et
