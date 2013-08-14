" ChangesPlugin.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.14
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Wed, 14 Aug 2013 22:10:39 +0200


" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 14 :AutoInstall: ChangesPlugin.vim


" ---------------------------------------------------------------------
"  Load Once: {{{1
if &cp || exists("g:loaded_changes")
 finish
endif
let g:loaded_changes       = 1
let s:keepcpo              = &cpo
set cpo&vim

let s:autocmd  = get(g:, 'changes_autocmd', 0)
" ------------------------------------------------------------------------------
" Public Interface: {{{1

" Define the Shortcuts:
com! -nargs=? -complete=file -bang EC	 EnableChanges<bang> <args>
com! DC	 DisableChanges
com! TCV ToggleChangeView
com! CC  ChangesCaption
com! CL  ChangesLinesOverview
com! CD  ChangesDiffMode

com! -nargs=? -complete=file -bang EnableChanges	call changes#EnableChanges(1, <q-bang>, <q-args>)
com! DisableChanges		call changes#CleanUp()
com! ToggleChangeView		call changes#TCV()
com! ChangesCaption		call changes#Output(1)
com! ChangesLinesOverview	call changes#EnableChanges(2, '')
com! ChangesDiffMode		call changes#EnableChanges(3, '')

if s:autocmd
    exe "try | call changes#Init() | catch | call changes#WarningMsg() | endtry"
    exe "au BufWinEnter,BufWritePost * call changes#EnableChanges(1, '')"
endif

au VimEnter * let g:changes_did_startup = 1

" Mappings:  "{{{1
if !hasmapto("[h")
    map <expr> <silent> [h changes#MoveToNextChange(0, v:count1)
endif
if !hasmapto("]h")
    map <expr> <silent> ]h changes#MoveToNextChange(1, v:count1)
endif

" Text-object: A hunk
if !hasmapto("ah", 'v')
    vmap <expr> <silent> ah changes#CurrentHunk()
endif

if !hasmapto("ah", 'o')
    omap <silent> ah :norm Vah<cr>
endif
    
" =====================================================================
" Restoration And Modelines: {{{1
" vim: fdm=marker
let &cpo= s:keepcpo
unlet s:keepcpo

" Modeline
" vi:fdm=marker fdl=0
