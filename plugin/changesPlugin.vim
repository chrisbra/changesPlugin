" ChangesPlugin.vim - Using Signs for indicating changed lines
" ---------------------------------------------------------------
" Version:  0.16
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Thu, 15 Jan 2015 21:16:40 +0100
" Script:  http://www.vim.org/scripts/script.php?script_id=3052
" License: VIM License
" Documentation: see :help changesPlugin.txt
" GetLatestVimScripts: 3052 15 :AutoInstall: ChangesPlugin.vim
" ---------------------------------------------------------------------
"  Load Once: {{{1
if &cp || exists("g:loaded_changes")
 finish
endif
let g:loaded_changes       = 1
let s:keepcpo              = &cpo
set cpo&vim
if v:version < 800 && !has('nvim')
    echohl WarningMsg
    echomsg "The ChangesPlugin needs at least a Vim version 8"
    echohl Normal
    finish
endif

" ---------------------------------------------------------------------
" Public Functions: {{{1
fu! ChangesMap(char) "{{{2
  if a:char is '<cr>'
    imap <silent><script> <cr> <cr><c-r>=changes#MapCR()<cr>
  endif
endfu

" Public Interface: {{{1
" Define the Shortcuts:
com! -nargs=? -complete=file EC  EnableChanges <args>
com! DC  DisableChanges
com! TCV ToggleChangeView
com! CC  ChangesCaption
com! CL  ChangesLinesOverview
com! CD  ChangesDiffMode
com! CT  ChangesStyleToggle
com! -nargs=? -bang CF ChangesFoldDiff <args>

com! -nargs=? -complete=file EnableChanges  call changes#EnableChanges(1, <q-args>)
com! DisableChanges   call changes#CleanUp()
com! ToggleChangeView   call changes#TCV()
com! ChangesCaption   call changes#Output()
com! ChangesLinesOverview call changes#EnableChanges(2)
com! ChangesDiffMode           call changes#EnableChanges(3)
com! ChangesStyleToggle   call changes#ToggleHiStyle()
com! -nargs=? ChangesFoldDifferences     call changes#FoldDifferences(<f-args>)
" Allow range, but ignore it (will be figured out from the diff)
com! -range -bang ChangesStageCurrentHunk  call changes#StageHunk(line('.'), !empty(<q-bang>))

if get(g:, 'changes_autocmd', 1)
  augroup ChangesPlugin
    au!
    au VimEnter * call s:ChangesStartup()
  augroup END
endif

function s:ChangesStartup()
  try
    call changes#Init()
  catch
    call changes#CleanUp()
  endtry
endfu
" =====================================================================
" Mappings:  "{{{1
if !hasmapto("changes#MoveToNextChange")
  if empty(maparg('[h'))
    map <expr> <silent> [h changes#MoveToNextChange(0, v:count1)
  endif
  if empty(maparg(']h'))
    map <expr> <silent> ]h changes#MoveToNextChange(1, v:count1)
  endif
endif

" Text-object: A hunk
if !hasmapto("ah", 'x') && empty(maparg('ah', 'x'))
  xmap <expr> <silent> ah changes#CurrentHunk()
endif

if !hasmapto("ah", 'o') && empty(maparg('ah', 'o'))
  omap <silent> ah :norm Vah<cr>
endif

if !hasmapto('<Plug>(ChangesStageHunk)') && empty(maparg('<Leader>h', 'n'))
  nmap     <silent><unique><nowait> <Leader>h <Plug>(ChangesStageHunk)
  nnoremap <unique><script> <Plug>(ChangesStageHunk) <sid>ChangesStageHunkAdd
  nnoremap <sid>ChangesStageHunkAdd :<c-u>call changes#StageHunk(line('.'), 0)<cr>
endif

if !hasmapto('<Plug>(ChangesStageHunkRevert)') && empty(maparg('<Leader>H', 'n'))
  nmap     <silent><unique><nowait> <Leader>H <Plug>(ChangesStageHunkRevert)
  nnoremap <unique><script> <Plug>(ChangesStageHunkRevert) <sid>ChangesStageHunkRevert
  nnoremap <sid>ChangesStageHunkRevert :<c-u>call changes#StageHunk(line('.'), 1)<cr>
endif

" In Insert mode, when <cr> is pressed, update the signs immediately
if !get(g:, 'changes_fast', 1) && !hasmapto('<cr>', 'i') && empty(maparg('<cr>', 'i'))
  call ChangesMap('<cr>')
endif

" Restoration And Modelines: {{{1
let &cpo=s:keepcpo
unlet s:keepcpo
" Modeline
" vi:fdm=marker fdl=0
