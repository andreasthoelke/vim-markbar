" BRIEF:    Somewhat user-facing interface for controlling the markbar UI.
" DETAILS:  The 'controller' in Model-View-Controller. Provides an abstract
"           interface for 'generating' markbars that can be manipulated
"           through implementation-defined keymappings.
"
"           Where possible, shared functionality between derived classes has
"           been factored up into this base class.
"
"           Some functions are declared pure virtual; these functions are
"           expected to exhibit special behavior based on the derived class,
"           and lack base class implementations.

" BRIEF:    Construct a MarkbarController object.
" PARAM:    model   (markbar#MarkbarModel)  Reference to the current markbar
"                                           state.
" PARAM:    view    (markbar#MarkbarView)   Reference to an object controlling
"                                           the appearance of the markbar UI.
function! markbar#MarkbarController#new(model, view) abort
    call markbar#MarkbarModel#AssertIsMarkbarModel(a:model)
    call markbar#MarkbarView#AssertIsMarkbarView(a:view)
    let l:new = {
        \ 'TYPE': 'MarkbarController',
        \ 'DYNAMIC_TYPE': [],
        \ '_markbar_model': a:model,
        \ '_markbar_view': a:view,
        \ 'openMarkbar':
            \ function('markbar#MarkbarController#openMarkbar'),
        \ 'closeMarkbar':
            \ function('markbar#MarkbarController#closeMarkbar'),
        \ 'toggleMarkbar':
            \ function('markbar#MarkbarController#toggleMarkbar'),
        \ '_getHelpText':
            \ function(
                \ 'markbar#MarkbarController#__noImplementation',
                \ ['_getHelpText']
            \ ),
        \ '_getMarkHeading':
            \ function('markbar#MarkbarController#_getMarkHeading'),
        \ '_getDefaultMarkName':
            \ function('markbar#MarkbarController#_getDefaultMarkName'),
        \ '_getDefaultNameFormat':
            \ function(
                \ 'markbar#MarkbarController#__noImplementation',
                \ ['_getDefaultNameFormat']
            \ ),
        \ '_getMarksToDisplay':
            \ function(
                \ 'markbar#MarkbarController#__noImplementation',
                \ ['_getMarksToDisplay']
            \ ),
        \ '_getMarkbarContents':
            \ function(
                \ 'markbar#MarkbarController#__noImplementation',
                \ ['_getMarkbarContents']
            \ ),
        \ '_generateMarkbarContents':
            \ function('markbar#MarkbarController#_generateMarkbarContents'),
        \ '_setMarkbarMappings':
            \ function(
                \ 'markbar#MarkbarController#__noImplementation',
                \ ['_setMarkbarMappings']
            \ ),
        \ '_openMarkbarSplit':
            \ function(
                \ 'markbar#MarkbarController#__noImplementation',
                \ ['_openMarkbarSplit']
            \ ),
        \ '_populateWithMarkbar':
            \ function('markbar#MarkbarController#_populateWithMarkbar'),
        \ '_setRefreshMarkbarAutocmds':
            \ function('markbar#MarkbarController#_setRefreshMarkbarAutocmds'),
    \ }

    return l:new
endfunction

function! markbar#MarkbarController#AssertIsMarkbarController(object) abort
    if type(a:object) !=# v:t_dict || a:object['TYPE'] !=# 'MarkbarController'
        throw '(markbar#MarkbarController) Object is not of type MarkbarController: ' . a:object
    endif
endfunction

" EFFECTS: - Create a markbar buffer for the currently active buffer if one
"           does not yet exist.
"           - Open this markbar buffer in a sidebar if the markbar is not yet
"           open, or refresh its contents if it is already open.
"           - Set autocmds to refresh the markbar buffer if it remains open.
function! markbar#MarkbarController#openMarkbar() abort dict
    call markbar#MarkbarController#AssertIsMarkbarController(l:self)
    let l:model = l:self['_markbar_model']
    let l:view  = l:self['_markbar_view']

    call l:model.updateCurrentAndGlobal()
    call l:self._openMarkbarSplit()

    let l:active_buffer  = l:model.getActiveBuffer()
    let l:markbar_buffer = l:view.getMarkbarBuffer()

    try
        call l:self._populateWithMarkbar(l:active_buffer, l:markbar_buffer)
    catch /Buffer not cached/
        " HACK: Assume that this buffer isn't a 'real' buffer;
        "       instead, push the 'actual open buffer' on top of it
        "       and let that be the 'active buffer'
        call l:view.closeMarkbar()
        let l:active_buffer = bufnr('%')
        call l:model.pushNewBuffer(l:active_buffer)
        call l:self._openMarkbarSplit()
        call l:self._populateWithMarkbar(l:active_buffer, l:markbar_buffer)
    endtry
    call l:self._setMarkbarMappings()
    call l:self._setRefreshMarkbarAutocmds()
endfunction

function! markbar#MarkbarController#closeMarkbar() abort dict
    call markbar#MarkbarController#AssertIsMarkbarController(l:self)
    return l:self['_markbar_view'].closeMarkbar()
endfunction

function! markbar#MarkbarController#toggleMarkbar() abort dict
    call markbar#MarkbarController#AssertIsMarkbarController(l:self)
    if l:self['_markbar_view'].closeMarkbar() | return | endif
    call l:self.openMarkbar()
endfunction

function! markbar#MarkbarController#__noImplementation(func_name, ...) abort dict
    call markbar#MarkbarController#AssertIsMarkbarController(l:self)
    throw '(markbar#MarkbarController) Invoked pure virtual function ' . a:func_name
endfunction

" RETURNS:  (v:t_string)    The given mark, reformatted into a markbar
"                           'section heading'.
" PARAM:    mark    (MarkData)  The mark for which to produce a heading.
function! markbar#MarkbarController#_getMarkHeading(mark) abort dict
    call markbar#MarkbarController#AssertIsMarkbarController(l:self)
    call markbar#MarkData#AssertIsMarkData(a:mark)
    let l:suffix = ' '
    let l:user_given_name = a:mark.getName()
    if empty(l:user_given_name)
        let l:suffix .= l:self._getDefaultMarkName(a:mark)
    else
        let l:suffix .= l:user_given_name
    endif
    " return "['" . a:mark.getMark() . ']:' . l:suffix
    " Style this slightly different
    return "|" . a:mark.getMark() . ' |' . l:suffix
endfunction

" RETURNS:  (v:t_string)    The 'default name' for the given mark, as
"                           determined by the global mark name format strings.
" PARAM:    mark    (markbar#MarkData)  The mark to be named.
function! markbar#MarkbarController#_getDefaultMarkName(mark) abort dict
    call markbar#MarkbarController#AssertIsMarkbarController(l:self)
    call markbar#MarkData#AssertIsMarkData(a:mark)
    let l:mark_char = a:mark.getMark()
    let l:format = l:self._getDefaultNameFormat(a:mark)
    let l:format_str = l:format[0]
    let l:format_arg = l:format[1]
    let l:name = ''
    if empty(l:format_str) | return l:name | endif

    let l:cmd = 'let l:name = printf(''' . l:format_str . "'"

    for l:Arg in l:format_arg " capital 'Arg' to handle funcrefs
        let l:cmd .= ', '
        if type(l:Arg) == v:t_func
            let l:cmd .= string(l:Arg(markbar#BasicMarkData#new(a:mark)))
        elseif l:Arg ==# 'line'
            let l:cmd .= a:mark.getLineNo()
        elseif l:Arg ==# 'col'
            let l:cmd .= a:mark.getColumnNo()
        elseif l:Arg ==# 'fname'
            " include quotes when concatenating onto l:cmd
            let l:cmd .= string(markbar#helpers#ParentFilename(l:mark_char))
        else
            throw '(MarkbarController#_getDefaultName) Unrecognized format argument: '
                \ . l:Arg
        endif
    endfor
    let l:cmd .= ')'
    execute l:cmd
    return l:name
endfunction

" REQUIRES: - `a:buffer_no` is not a markbar buffer.
"           - `a:buffer_no` is not the global buffer.
"           - `a:buffer_no` is a buffer *number.*
" EFFECTS:  Return a list populated linewise with the requested marks
"           and those marks' contexts, with a few given parameters.
" PARAM:    marks   (v:t_string)    Every mark that the user wishes to
"                                   display, in order from left to right (i.e.
"                                   first character is the mark that should
"                                   appear at the top of the markbar.)
" PARAM:    highlight_mark  (v:t_bool)  Whether to add the 'mark marker'
"                                       character used to highlight the mark's
"                                       location in the context.
" PARAM:    backtick_like   (v:t_bool)  Whether to highlight the exact
"                                       position of the mark (`v:true`), or
"                                       the first non-whitespace character in
"                                       the line. Does nothing if
"                                       `a:highlight_mark` is false.
function! markbar#MarkbarController#_generateMarkbarContents(
    \ buffer_no,
    \ marks,
    \ section_separator,
    \ indent_block,
    \ highlight_mark,
    \ backtick_like
\ ) abort dict
    call markbar#MarkbarController#AssertIsMarkbarController(l:self)
    let l:markbar_model = l:self['_markbar_model']
    let l:marks =
        \ l:markbar_model.getBufferCache(a:buffer_no, v:true)['marks_dict']
    let l:globals =
        \ l:markbar_model.getBufferCache(
            \ markbar#constants#GLOBAL_MARKS())['marks_dict']

    let l:lines = [] " to return

    let l:i = -1
    while l:i <# len(a:marks)
        let l:i += 1
        let l:mark_char = a:marks[l:i]

        if !has_key(l:marks, l:mark_char) && !has_key(l:globals, l:mark_char)
            continue
        endif

        let l:mark =
            \ markbar#helpers#IsGlobalMark(l:mark_char) ?
                \ l:globals[l:mark_char] : l:marks[l:mark_char]
        let l:lines += [ l:self._getMarkHeading(l:mark) ]

        if !a:highlight_mark
            for l:line in l:mark['_context']
                let l:lines += [a:indent_block . l:line]
            endfor
        else
            " insert the mark marker at the mark's line, column in the context
            let l:marker    = markbar#settings#MarkMarker()
            let l:context   = l:mark['_context']
            let l:size      = len(l:context)
            let l:mark_line = l:size / 2

            let l:j = 0 | while l:j <# l:size
                let l:line = l:context[l:j]
                if l:j ==# l:mark_line
                    let l:colno = (a:backtick_like) ?
                        \ l:mark.getColumnNo() : matchstrpos(l:line, '\S')[1]
                    let l:parts = markbar#helpers#SplitString(l:line, l:colno)
                    let l:line = l:parts[0].l:marker.l:parts[1]
                endif
                let l:next_line = a:indent_block . l:line
                let l:lines += [l:next_line]
            let l:j += 1 | endwhile
        endif

        let l:lines += a:section_separator
    endwhile

    return l:lines
endfunction

" BRIEF:    Replace the target buffer with the marks/contexts of the given buffer.
function! markbar#MarkbarController#_populateWithMarkbar(
    \ for_buffer_no,
    \ into_buffer_expr
\ ) abort dict
    call markbar#MarkbarController#AssertIsMarkbarController(l:self)
    let l:contents  = l:self._getHelpText(l:self['_markbar_view'].getShouldShowHelp())
    let l:contents += l:self._getMarkbarContents(
        \ a:for_buffer_no,
        \ l:self._getMarksToDisplay()
    \ )
    call markbar#helpers#ReplaceBuffer(a:into_buffer_expr, l:contents)
endfunction

" BRIEF:    Set autocmds to refresh the markbar with this controller instance.
function! markbar#MarkbarController#_setRefreshMarkbarAutocmds() abort dict
    let g:__active_controller = l:self
    augroup vim_markbar_refresh
        au!
        " autocmd BufEnter,BufLeave,TextChanged,CursorHold,FileChangedShellPost
        " TODO can I live with less frequent updates? e.g. changed text is not updated right away
        autocmd BufEnter,BufLeave
            \ * call markbar#ui#RefreshMarkbar(g:__active_controller)
    augroup end
endfunction
