" ChangesPlugin.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.13
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Sat, 16 Feb 2013 23:17:36 +0100


" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 13 :AutoInstall: ChangesPlugin.vim


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

com! -nargs=? -complete=file -bang EnableChanges	call changes#GetDiff(1, <q-bang>, <q-args>)
com! DisableChanges		call changes#CleanUp()
com! ToggleChangeView		call changes#TCV()
com! ChangesCaption		call changes#Output(1)
com! ChangesLinesOverview	call changes#GetDiff(2, '')
com! ChangesDiffMode		call changes#GetDiff(3, '')

if s:autocmd
    exe "try | call changes#Init() | catch | call changes#WarningMsg() | endtry"
    exe "au BufWinEnter,BufWritePost * call changes#GetDiff(1, '')"
endif

au VimEnter * let g:changes_did_startup = 1
" =====================================================================
" Restoration And Modelines: {{{1
" vim: fdm=marker
let &cpo= s:keepcpo
unlet s:keepcpo

" Modeline
" vi:fdm=marker fdl=0
