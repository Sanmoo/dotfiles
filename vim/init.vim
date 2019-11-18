call plug#begin('~/.local/share/nvim/plugged')
Plug 'tpope/vim-sensible'
Plug 'ludovicchabant/vim-gutentags'
Plug 'ternjs/tern_for_vim', { 'do': 'npm install && npm install -g tern' }
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'w0rp/ale'
Plug 'altercation/vim-colors-solarized'
Plug 'iCyMind/NeoSolarized'
Plug 'suy/vim-context-commentstring'
Plug 'hail2u/vim-css3-syntax'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-repeat'
Plug 'scrooloose/nerdtree'
Plug 'easymotion/vim-easymotion'
Plug 'jiangmiao/auto-pairs'
Plug 'autozimu/LanguageClient-neovim', {
    \ 'branch': 'next',
    \ 'do': 'bash install.sh',
    \ }
Plug 'SirVer/ultisnips'
Plug 'honza/vim-snippets'
Plug 'neoclide/coc.nvim', {'do': { -> coc#util#install()}}

" Infinite Fun 
Plug 'rbtnn/game_engine.vim'
Plug 'rbtnn/mario.vim'
Plug 'sheerun/vim-polyglot'
call plug#end()

" My Preferred colorscheme *--*
colorscheme NeoSolarized

" UltiSnips config
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"

" Tern Config 
let g:tern_request_timeout = 1
let g:tern_request_timeout = 6000
let g:tern#command = ["tern"]
let g:tern#arguments = [" — persistent"]

" ALE config
let g:ale_sign_error = '❌'
let g:ale_sign_warning = '⚠️'
let g:ale_fixers = {'javascript': ['eslint'], 'ruby': ['rubocop']}
let g:ale_fix_on_save = 1
let g:ale_linters = {'java': []}

" CoC config 
" O

" FZF config
nnoremap <C-p> :FZF<CR>
nnoremap <Leader>b :Buffers<CR>
nnoremap <Leader>h :History<CR>
nnoremap <Leader>t :BTags<CR>
nnoremap <Leader>T :Tags<CR>

" NERDTree config
let NERDTreeIgnore=['\.git$', '\.nvimrc$', 'tags$', 'tags\.lock$', 'tags\.temp$']

" "################### Custon NO-PLUGIN CONFIG ###############

" Turn off highlight match on press enter
nnoremap <CR> :noh<CR><CR>                           

" Search case sensitive only when use Capitals letters to find
:set ignorecase
:set smartcase

"Copy/Paste to clipboard on selection+Y/P
noremap Y "+y

"navigate panes with ctrl jklh
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

"open current file in NERDTree
nmap ,c :NERDTreeFind<CR>

" from Ryan florence -> https://gist.github.com/ryanflorence/6d92b7495873263aec0b4e3c299b3bd3
" Keep the error column always visible (jumpy when linter runs on input)
:set signcolumn=yes

"show line number and relative line number
set nu

" Indent using spaces instead of tabs
set expandtab

" Dont wrap lines
set nowrap

" The number of spaces to use for each indent
set shiftwidth=2

" Number of spaces to use for a <Tab> during editing operations
set softtabstop=2

" Add this option to avoid issues with webpack
:set backupcopy=yes

" Allow executing local .rc files
set exrc
set secure
