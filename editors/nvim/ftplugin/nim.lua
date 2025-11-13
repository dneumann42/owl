if vim.b.owl_nim_diagnostic_mapping == 1 then
  return
end
vim.b.owl_nim_diagnostic_mapping = 1

local diagnostics = vim.diagnostic
if not diagnostics then
  return
end

-- Use Ctrl-K to show diagnostics for the token under the cursor.
vim.keymap.set('n', '<C-k>', function()
  diagnostics.open_float(nil, { scope = 'cursor', focus = false })
end, { buffer = 0, silent = true, desc = 'Show diagnostics under cursor' })
