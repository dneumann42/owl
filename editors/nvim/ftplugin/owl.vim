if exists("b:did_ftplugin_owl")
  finish
endif
let b:did_ftplugin_owl = 1

setlocal commentstring=;;\ %s
setlocal formatoptions-=t
setlocal iskeyword+=-
setlocal iskeyword+=#
setlocal iskeyword+=$
