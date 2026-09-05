rockspec_format = '3.0'
package = "bunsetsu.nvim"
version = "scm-1"
source = {
  url = "git+https://github.com/kasi-x/bunsetsu.nvim"
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
