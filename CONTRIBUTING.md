# Contributing to bunsetsu.nvim

Issues and pull requests are welcome. This document describes the development
workflow and the conventions used in this repository.

## Development setup

Requirements:

- Neovim 0.11+ (CI tests 0.11, 0.12, stable, nightly)
- [luarocks](https://luarocks.org/) (provides `busted` and `luacheck`)
- [stylua](https://github.com/JohnnyMorganz/StyLua)

```sh
# tests (the bundled TinySegmenter runs in pure Lua; no external binaries needed)
eval $(luarocks path --lua-version 5.1 --bin)
busted .

# lint / format
make luacheck
make stylua          # format in place
make check-stylua    # check only
```

## Conventions

- **Style**: StyLua (`.stylua.toml`, 2-space indent) and luacheck
  (`.luacheckrc`) must pass. CI runs both.
- **Tests**: each module has a matching `spec/bunsetsu/*_spec.lua`. Tests must
  not require external binaries or network access — external tokenizers are
  stubbed (`spec/stub_tokenizer.lua`, module-level mocks), and dictionary
  fixtures are written to temporary files.
- **Documentation**:
  - `README.md` (English) is user-facing entry point.
  - `doc/bunsetsu.txt` (Japanese vimdoc) is the full reference — keep it in
    sync with the README and run `nvim --headless -u NONE -c 'helptags doc' -c 'qa!'`
    after editing.
  - Every `|tag|` reference in the help must resolve; `spec/bunsetsu/doc_spec.lua`
    enforces this.
- **Commits / PR titles**: conventional commits, lowercase subject
  (`feat: ...`, `fix: ...`). The release workflow publishes tagged versions;
  the changelog ([Keep a Changelog](https://keepachangelog.com/en/1.0.0/))
  must be updated for user-visible changes.

## Releasing

1. Update `CHANGELOG.md` (move Unreleased to a new version section) and
   `doc/news.txt`.
2. Tag and push: `git tag -a vX.Y.Z && git push origin vX.Y.Z` — the Release
   workflow uploads to LuaRocks **only when the `LUAROCKS_API_KEY` repository
   secret is set**; otherwise the tag alone distributes the release.
3. If the key is added later, re-run publishing via
   *Actions → Release → Run workflow* (workflow_dispatch) or re-push the tag.
4. Validate the rock locally first: `luarocks lint bunsetsu.nvim-scm-1.rockspec`
   and `luarocks pack bunsetsu.nvim-scm-1.rockspec`.

## Design notes

- Motion and jumping integrate with [nvim-spider](https://github.com/chrisgrieser/nvim-spider)
  and [flash.nvim](https://github.com/folke/flash.nvim) instead of
  reimplementing them. Selection/operator handling goes through spider's
  `setEndpoints`.
- The bundled TinySegmenter is the default backend; Vibrato/Vaporetto are
  optional external backends behind the same segmentation interface
  (`lua/bunsetsu/_core/segment.lua`).
- Anything user-visible needs a spec: motions, text objects, regions — pure
  logic lives in `_core/` and is tested without Neovim side effects where
  possible.
