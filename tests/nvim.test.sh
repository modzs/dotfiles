#!/usr/bin/env bash
# Behaviour tests for the Neovim plugin declarations.
#
# lua/plugins/ is loaded wholesale by `require('lazy').setup('plugins')`, so a
# file that does not compile, or that returns something other than a table,
# breaks every plugin in the config rather than just itself. And lazy.nvim only
# writes a lazy-lock.json entry for a plugin it has actually installed, so a
# spec committed without its pin is invisible until someone clones the repo on
# a new machine and gets a different revision than the author is running.
#
# Neovim itself is the interpreter here, for the same reason the other suites
# use real parsers: it is what actually loads these files.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dotfiles_test_parse_args "$@"

NVIM_CONFIG=$ROOT/home/.config/nvim

# --- every plugin file is loadable and declares its pin ------------------------
#
# Both checks come from one nvim run because both need the same thing: the
# specs, as Lua values rather than as text. `--clean` keeps the machine's own
# config out of it, so the suite tests this repository and not the user.

test_plugin_specs_are_loadable_and_pinned() {
  local script status=0 output

  if ! command -v nvim >/dev/null 2>&1; then
    skip "nvim plugin spec check (nvim not found)"
    skip "nvim lazy-lock.json pin check (nvim not found)"
    return 0
  fi

  script=$(dotfiles_test_tmproot dotfiles-nvim)/specs.lua
  cat >"$script" <<'LUA'
local config = _G.arg[1]
local dir = config .. '/lua/plugins'

local function die(message)
  io.stderr:write(message .. '\n')
  os.exit(1)
end

-- Every plugin lazy is asked to manage, keyed the way lazy keys the lock file:
-- the last path segment of the repo, unless the spec renames it with `name`.
local declared = {}

local function collect(spec, where)
  if type(spec) ~= 'table' then
    die(where .. ' declares a ' .. type(spec) .. ' where a plugin spec belongs')
  end
  local repo = spec[1]
  if type(repo) == 'string' then
    declared[spec.name or repo:match('[^/]+$')] = repo
  end
  for _, dep in ipairs(spec.dependencies or {}) do
    if type(dep) == 'string' then
      declared[dep:match('[^/]+$')] = dep
    else
      collect(dep, where)
    end
  end
end

local files = vim.fn.readdir(dir)
if #files == 0 then
  die(dir .. ' has no plugin files, so nothing was checked')
end

for _, file in ipairs(files) do
  local path = dir .. '/' .. file
  local chunk, err = loadfile(path)
  if not chunk then
    die('lua/plugins/' .. file .. ' does not compile: ' .. err)
  end
  local ok, value = pcall(chunk)
  if not ok then
    die('lua/plugins/' .. file .. ' errored when loaded: ' .. tostring(value))
  end
  if type(value) ~= 'table' then
    die('lua/plugins/' .. file .. ' returns ' .. type(value) .. ', not a table')
  end
  -- A file is either one spec (repo string first) or a list of them.
  if type(value[1]) == 'string' then
    collect(value, 'lua/plugins/' .. file)
  else
    for _, spec in ipairs(value) do
      collect(spec, 'lua/plugins/' .. file)
    end
  end
end

local handle = io.open(config .. '/lazy-lock.json', 'r')
if not handle then
  die('lazy-lock.json is missing, so no plugin in this config is pinned')
end
local body = handle:read('*a')
handle:close()
local ok, lock = pcall(vim.json.decode, body)
if not ok or type(lock) ~= 'table' then
  die('lazy-lock.json is not valid JSON: ' .. tostring(lock))
end

local unpinned = {}
for name, repo in pairs(declared) do
  if lock[name] == nil then
    table.insert(unpinned, repo .. ' (expected a "' .. name .. '" entry)')
  end
end
if #unpinned > 0 then
  table.sort(unpinned)
  die('declared but absent from lazy-lock.json: ' .. table.concat(unpinned, ', '))
end

io.write(tostring(vim.tbl_count(declared)) .. '\n')
LUA

  output=$(nvim --clean -l "$script" "$NVIM_CONFIG" 2>&1) || status=$?

  if [ "$status" -ne 0 ]; then
    fail "nvim plugin specs: $output"
  fi

  pass "nvim: every file in lua/plugins/ loads and returns a table"
  pass "nvim: all $output declared plugins have a lazy-lock.json pin"
}

test_plugin_specs_are_loadable_and_pinned

test_summary
