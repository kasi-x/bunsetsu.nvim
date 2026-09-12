rockspec_format = '3.0'
package = "bunsetsu.nvim"
version = "scm-1"
source = {
  url = "git+https://github.com/kasi-x/bunsetsu.nvim"
}
description = {
  summary = "Move by Japanese phrase units (bunsetsu) in Neovim",
  detailed = [[
bunsetsu.nvim moves w/b/e/ge by Japanese phrase boundaries using a bundled
TinySegmenter port (offline, no external binaries) or optional Vibrato /
Vaporetto tokenizers. It extends nvim-spider and flash.nvim, and provides
sentence-end motion with indirect-quote handling, sentence/phrase text
objects, POS highlighting and lemma lookup.]],
  homepage = "https://github.com/kasi-x/bunsetsu.nvim",
  license = "MIT",
  issues_url = "https://github.com/kasi-x/bunsetsu.nvim/issues",
}
dependencies = {
}
test_dependencies = {
  "nlua"
}
build = {
  type = "builtin",
  copy_directories = {
    'plugin',
    'doc',
  },
}
