ignore = {
  "631",    -- max_line_length
  "611",    -- line is too long
  "212",    -- unused argument
  "213",    -- unused loop variable
  "214",    -- unused local variable
  "542",    -- empty if branch (スキップを意図した分岐を許容)
}
read_globals = {
  "vim",
  "describe",
  "it",
  "assert",
  "before_each",
  "after_each",
  "unpack",
}
-- vim.g.loaded_bunsetsu 等の書き込みを許容する
globals = {
  "vim.g",
}
