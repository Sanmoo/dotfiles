ln -fs "$(pwd)/zsh/.zshrc" ~/.zshrc
ln -fs "$(pwd)/vim/init.vim" ~/.config/nvim/init.vim
ln -fs "$(pwd)/tmux/.tmux.conf.local" ~/.tmux.conf.local
git config --global core.excludesfile "$(pwd)/git/.gitignore_global" 
