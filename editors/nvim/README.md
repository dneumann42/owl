# Owl Neovim Support

Copy the files in this directory into a location that Neovim/Vim searches for runtime files. A minimal setup looks like:

```bash
mkdir -p ~/.config/nvim/{ftdetect,ftplugin,syntax}
cp editors/nvim/ftdetect/owl.vim ~/.config/nvim/ftdetect/
cp editors/nvim/ftplugin/owl.vim ~/.config/nvim/ftplugin/
cp editors/nvim/ftplugin/nim.lua ~/.config/nvim/ftplugin/
cp editors/nvim/syntax/owl.vim ~/.config/nvim/syntax/
```

After copying, opening a file with the `.owl` extension will automatically enable Owl highlighting and file-type specific settings. Nim buffers also pick up a `<C-k>` mapping that shows diagnostics for the item under the cursor.
