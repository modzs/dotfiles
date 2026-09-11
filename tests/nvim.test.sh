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
TMP_ROOT=$(dotfiles_test_tmproot dotfiles-nvim)

# The collector: takes a config directory, prints "<lua files> <plugins>", and
# exits non-zero naming whatever is wrong. Both tests below run this same file,
# one against the repository and one against a fixture, so the fixture really
# does exercise the code the repository check depends on.
SPEC_SCRIPT=$TMP_ROOT/specs.lua
cat >"$SPEC_SCRIPT" <<'LUA'
local config = _G.arg[1]
local dir = config .. '/lua/plugins'

local function die(message)
  io.stderr:write(message .. '\n')
  os.exit(1)
end

-- Every plugin lazy is asked to manage, keyed the way lazy keys the lock file:
-- the last path segment of the repo, unless the spec renames it with `name`.
local declared = {}

local function is_list(value)
  local n = 0
  for _ in pairs(value) do
    n = n + 1
    if value[n] == nil then
      return false
    end
  end
  return true
end

-- Mirrors lazy.nvim's Spec:normalize, which takes its list branch on
-- `#spec > 1 or is_list(spec)`. That distinction is the whole point: lazy reads
-- `{ 'a/b', 'c/d' }` as two plugins, not as one spec with a stray second field,
-- and a collector that guessed otherwise would silently miss the second pin.
-- Dependencies go back through here because lazy normalizes them the same way,
-- which is what makes the single-string `dependencies = 'a/b'` form work.
local function normalize(spec, where)
  if type(spec) == 'string' then
    declared[spec:match('[^/]+$')] = spec
    return
  end
  if type(spec) ~= 'table' then
    die(where .. ' declares a ' .. type(spec) .. ' where a plugin spec belongs')
  end
  if #spec > 1 or is_list(spec) then
    for _, entry in ipairs(spec) do
      normalize(entry, where)
    end
    return
  end
  local repo = spec[1]
  if type(repo) == 'string' then
    declared[spec.name or repo:match('[^/]+$')] = repo
  elseif spec.dir == nil then
    die(where .. ' declares a spec this check cannot interpret, so its pin cannot be checked')
  end
  if spec.dependencies ~= nil then
    normalize(spec.dependencies, where)
  end
end

-- lazy loads the .lua files out of this directory and ignores anything else,
-- so a README or a subdirectory next to the specs must not fail the check.
local files = {}
for _, name in ipairs(vim.fn.readdir(dir)) do
  if name:sub(-4) == '.lua' and vim.fn.filereadable(dir .. '/' .. name) == 1 then
    table.insert(files, name)
  end
end
if #files == 0 then
  die(dir .. ' has no .lua plugin files, so nothing was checked')
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
  normalize(value, 'lua/plugins/' .. file)
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

io.write(tostring(#files) .. ' ' .. tostring(vim.tbl_count(declared)) .. '\n')
LUA

# --- every plugin file is loadable and declares its pin ------------------------
#
# Both checks come from one nvim run because both need the same thing: the
# specs, as Lua values rather than as text. `--clean` keeps the machine's own
# config out of it, so the suite tests this repository and not the user.

test_plugin_specs_are_loadable_and_pinned() {
  local status=0 output files plugins

  if ! command -v nvim >/dev/null 2>&1; then
    skip "nvim plugin spec check (nvim not found)"
    skip "nvim lazy-lock.json pin check (nvim not found)"
    return 0
  fi

  output=$(nvim --clean -l "$SPEC_SCRIPT" "$NVIM_CONFIG" 2>&1) || status=$?

  if [ "$status" -ne 0 ]; then
    fail "nvim plugin specs: $output"
  fi

  files=${output%% *}
  plugins=${output##* }

  pass "nvim: all $files .lua files in lua/plugins/ load and return a table"
  pass "nvim: all $plugins declared plugins have a lazy-lock.json pin"
}

# --- the collector understands every shape lazy accepts ------------------------
#
# The guard is only worth its output if it sees every declaration lazy sees: a
# file returning bare repo strings, a single-string `dependencies`, and a
# directory holding something that is not Lua. Miss one and it prints ok for a
# plugin nothing in the repository pins - the exact regression it exists to
# catch. The fixture is a config directory of its own, checked by the same
# script the repository check runs.

test_spec_collector_sees_every_declaration_shape() {
  local fixture plugins status output

  if ! command -v nvim >/dev/null 2>&1; then
    skip "nvim spec collector shape check (nvim not found)"
    return 0
  fi

  fixture=$TMP_ROOT/fixture
  plugins=$fixture/lua/plugins
  mkdir -p "$plugins" || fail "could not create the collector fixture"

  printf "return { 'owner/alpha.nvim', 'owner/beta.nvim' }\n" >"$plugins/pair.lua"
  printf "return { { 'owner/gamma.nvim', dependencies = 'owner/delta.nvim' } }\n" >"$plugins/deps.lua"
  printf 'Not a plugin file.\n' >"$plugins/README.md"

  cat >"$fixture/lazy-lock.json" <<'JSON'
{
  "alpha.nvim": { "branch": "main", "commit": "0000000000000000000000000000000000000000" },
  "beta.nvim": { "branch": "main", "commit": "0000000000000000000000000000000000000000" },
  "gamma.nvim": { "branch": "main", "commit": "0000000000000000000000000000000000000000" },
  "delta.nvim": { "branch": "main", "commit": "0000000000000000000000000000000000000000" }
}
JSON

  status=0
  output=$(nvim --clean -l "$SPEC_SCRIPT" "$fixture" 2>&1) || status=$?
  if [ "$status" -ne 0 ]; then
    fail "nvim spec collector rejected a fully pinned config: $output"
  fi
  if [ "$output" != "2 4" ]; then
    fail "nvim spec collector reported '$output', expected '2 4' (files, plugins)"
  fi

  cat >"$fixture/lazy-lock.json" <<'JSON'
{
  "alpha.nvim": { "branch": "main", "commit": "0000000000000000000000000000000000000000" },
  "gamma.nvim": { "branch": "main", "commit": "0000000000000000000000000000000000000000" }
}
JSON

  status=0
  output=$(nvim --clean -l "$SPEC_SCRIPT" "$fixture" 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then
    fail "nvim spec collector passed a config with two unpinned plugins"
  fi
  assert_contains "$output" 'owner/beta.nvim' \
    "nvim spec collector missed the second plugin of a two-string file: $output"
  assert_contains "$output" 'owner/delta.nvim' \
    "nvim spec collector missed a single-string dependency: $output"

  pass "nvim: the pin guard reads list files and string dependencies, and ignores non-Lua files"

  # A spec lazy manages but this check cannot name - `{ import = ... }`, a url-only
  # spec - has to stop the run. Passing over it quietly is how the guard would keep
  # printing a healthy total while covering less than it claims.
  printf "return { { import = 'plugins.extra' } }\n" >"$plugins/opaque.lua"

  status=0
  output=$(nvim --clean -l "$SPEC_SCRIPT" "$fixture" 2>&1) || status=$?
  rm -f "$plugins/opaque.lua"
  if [ "$status" -eq 0 ]; then
    fail "nvim spec collector passed over a spec it cannot interpret"
  fi
  assert_contains "$output" 'opaque.lua' \
    "nvim spec collector did not name the file holding the spec it cannot interpret: $output"

  pass "nvim: the pin guard refuses a spec it cannot interpret instead of skipping it"
}

# --- the preview command works on the first try, in a real session -------------
#
# markdown-preview.nvim defines its three commands with `command! -buffer` from
# its own BufEnter/FileType autocmd, so merely sourcing the plugin gives them to
# no buffer. Declared with `cmd` alone, the first `:MarkdownPreviewToggle` of a
# session loads the plugin, finds no command to hand the invocation to, and
# leaves none behind - lazy has already deleted its own stub, so retyping it
# gives E492. This repository shipped that spec once, which is why the check
# drives the real config through lazy and asks for the preview the way a user
# does, rather than reading the spec file: a spec that does not work reads the
# same as one that does.
#
# Installing the plugins needs the network, which puts this in the same class as
# tests/nixpkgs-channel.test.sh: it reports skip, never ok, when it cannot run.
#
# Two boundaries are deliberate. The scratch run neutralises markdown-preview's
# `build` by handing lazy a shell that does nothing: no assertion here depends on
# the built server - mkdp reports a missing one rather than throwing - so pulling
# its npm dependency tree on every run would be cost with no coverage behind it.
# And the network calls are not bounded: macOS ships no `timeout`, so capping
# them would mean building a timer inside nvim. CI's job-level timeout is the
# backstop, and a local run can be interrupted.

test_preview_command_works_as_the_first_command() {
  local session config data mkdp outcome exists

  if ! command -v nvim >/dev/null 2>&1; then
    skip "nvim markdown preview command check (nvim not found)"
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    skip "nvim markdown preview command check (git not found)"
    return 0
  fi

  session=$TMP_ROOT/session
  config=$session/config
  data=$session/data
  mkdir -p "$config" "$data" "$session/state" "$session/cache" \
    || fail "could not create the nvim session scratch directories"

  # lazy writes its lock file into stdpath('config'), and installing plugins is
  # exactly what this does, so the config it drives is a copy. The tracked
  # lazy-lock.json is an input here, never an output.
  cp -R "$NVIM_CONFIG" "$config/nvim" || fail "could not copy the nvim config"

  cat >"$session/noop.vim" <<'VIM'
function! MkdpTestNoop(url) abort
endfunction
let g:mkdp_browserfunc = 'MkdpTestNoop'
VIM

  cat >"$session/probe.lua" <<'LUA'
-- `:MarkdownPreviewToggle` as the first command of the session, on a markdown
-- buffer that was already open before it was typed. Both halves are recorded:
-- the invocation can look fine while the command it needed no longer exists.
-- Nothing stops the preview here; the server is a job of this nvim, so quitting
-- takes it down. `:MarkdownPreviewStop` would not - it blocks on an rpcrequest
-- the server never answers when no page has been opened yet.
local out = assert(io.open(os.getenv('MKDP_PROBE_OUT'), 'w'))
local ok = pcall(vim.cmd, 'MarkdownPreviewToggle')
out:write(tostring(ok) .. ' ' .. tostring(vim.fn.exists(':MarkdownPreviewToggle')) .. '\n')
out:close()
LUA

  printf '# note\n\nBody text.\n' >"$session/note.md"

  env XDG_CONFIG_HOME="$config" XDG_DATA_HOME="$data" XDG_STATE_HOME="$session/state" \
    XDG_CACHE_HOME="$session/cache" SHELL=/usr/bin/true \
    nvim --headless -c 'quitall!' >"$session/install.log" 2>&1

  # lua/plugin.lua clones lazy.nvim before it asks lazy for anything, so its
  # presence is this run's proof that git and the network worked. Past that
  # point a missing markdown-preview.nvim is a defect in the spec, not an
  # environment this check could not run in.
  mkdp=$data/nvim/lazy/markdown-preview.nvim
  if [ ! -d "$data/nvim/lazy/lazy.nvim" ]; then
    skip "nvim markdown preview command check (lazy.nvim could not be installed)"
    return 0
  fi
  if [ ! -f "$mkdp/plugin/mkdp.vim" ]; then
    fail "nvim markdown preview: lazy installed but markdown-preview.nvim did not - lua/plugins/markdown.lua no longer declares it, or declares it disabled or misnamed"
  fi

  env XDG_CONFIG_HOME="$config" XDG_DATA_HOME="$data" XDG_STATE_HOME="$session/state" \
    XDG_CACHE_HOME="$session/cache" MKDP_PROBE_OUT="$session/probe.txt" \
    nvim --headless --cmd "source $session/noop.vim" "$session/note.md" \
      -c "luafile $session/probe.lua" -c 'quitall!' >"$session/session.log" 2>&1

  if [ ! -f "$session/probe.txt" ]; then
    fail "nvim markdown preview: the session recorded no result: $(cat "$session/session.log")"
  fi
  read -r outcome exists <"$session/probe.txt"

  if [ "$outcome" != "true" ]; then
    fail "nvim markdown preview: :MarkdownPreviewToggle raised an error on a markdown buffer"
  fi
  if [ "$exists" != "2" ]; then
    fail "nvim markdown preview: exists(':MarkdownPreviewToggle') is $exists after the first invocation, not 2 - mkdp defines its commands buffer-locally from an autocmd, so the spec needs ft = 'markdown' to have them in a buffer that is already open"
  fi

  pass "nvim: :MarkdownPreviewToggle runs and survives as the first command of a session"
}

test_plugin_specs_are_loadable_and_pinned
test_spec_collector_sees_every_declaration_shape
test_preview_command_works_as_the_first_command

test_summary
