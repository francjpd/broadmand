# broadmand

![broadmand logo](broadmand.png)

Broadcast a shell command to every pane of the active tmux window — or,
inside [Herdr](https://herdr.dev), every pane of the active Herdr workspace.
Ships with a modal-style `cd` picker and a free-form command broadcaster.

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│   prefix d →   ┌── broadcast command ──────────────┐         │
│                │                                   │         │
│                │  > make test                      │         │
│                │                                   │         │
│                └───────────────────────────────────┘         │
│                                                              │
│   prefix D →   ┌── pick directory ─────────────────┐         │
│                │   .config/                        │         │
│                │   projects/                       │         │
│                │   Documents/                      │         │
│                │ ▸ Downloads/                      │         │
│                │   …                               │         │
│                └───────────────────────────────────┘         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Quick start

- **`prefix d`** — broadcast a free-form shell command to every pane
  in the current window (including the active one).
  Type a command, press `Enter`, and each pane receives it.  The popup
  starts in the active pane's working directory, and `Tab` cycles
  through file and directory completions like zsh `menu-complete`
  (Shift-`Tab` cycles backward).

- **`prefix D`** — pick a directory with `fzf`, then broadcast
  `cd <picked-directory>` to every pane (including the active one).
  The initial list combines the active pane's cwd with `$HOME`, so the
  picker is useful from anywhere. Type to fuzzy-filter that list. If
  the typed text is an existing directory path, the list switches to
  that directory plus its subdirectories.

Panes running excluded commands (editors, `ssh`, `htop`, …) or currently
in copy mode are skipped automatically. A short status message flashes
in the tmux status line when the broadcast finishes.

## Herdr support

When broadmand runs inside a [Herdr](https://herdr.dev) pane — Herdr sets
`HERDR_ENV=1` there — it targets the active Herdr workspace instead of the
active tmux window. The free-form broadcaster and the modal `cd` picker both
work: they enumerate the panes of the workspace the captain is currently in,
skip panes running excluded commands, and send the command to each remaining
pane, exactly like the tmux path targets every pane of the active window.

Detection is a single check: if `HERDR_ENV` is `1`, broadmand talks to
`herdr`; otherwise the tmux path is used unchanged. Under Herdr the scripts:

- resolve the active pane with `herdr pane current --current` (its
  `workspace_id` is the active workspace),
- enumerate that workspace's panes with `herdr pane list --workspace <id>`,
- read each pane's foreground command with `herdr pane process-info` for the
  excluded-command skip, and
- send input with `herdr pane send-keys` / `herdr pane run`.

If the active workspace cannot be resolved unambiguously, broadmand fails
with a clear message rather than broadcasting to the wrong panes.

The `prefix d` / `prefix D` bindings are tmux features; under Herdr the same two
behaviours are installed and bound through the plugin entrypoints, actions, and
keybindings described under [Install under Herdr](#install-under-herdr).

Herdr has no `@-option` surface, so under Herdr the configuration values
(`@broadcast-excluded`, `@broadcast-picker-engine`, `@broadcast-pane-delay`)
fall back to the built-in defaults.

## Features

- **Native Tab cycling in the command popup** — `prefix d` starts in the
  active pane's working directory; `Tab` cycles through file and
  directory completions (zsh-style `menu-complete`) and Shift-`Tab`
  cycles backward. The full match list is shown when there's no common
  prefix to insert.
- **Broadcast any command** — `prefix d` opens an empty input; the typed
  command is sent to every pane in the active window.
- **`cd-all` picker** — `prefix D` opens an `fzf` directory picker and
  broadcasts `cd <dir>` to all panes including the active one.
- **Reusable modal primitive** — `scripts/popup.sh` is a generic single-line
  input box; future features build on it.
- **Pluggable picker** — backed by `fd` (default), `zoxide`, or both.
- **Safe by default** — skips panes running editors (`vim`, `vi`, `nvim`,
  `less`, `man`, `mc`), `ssh`, system monitors (`htop`, `top`), and panes
  currently in copy mode. The list is configurable.

## Requirements

- tmux **3.3 or newer** — the popups use `display-popup -T`, added in
  tmux 3.3
- bash **3.2 or newer** (the macOS system bash is sufficient)
- `fzf` (used by the directory picker)
- `fd` or `zoxide` (picker engine; install the one matching
  `@broadcast-picker-engine`)
- `herdr` (optional — only for the Herdr workspace path)

### Platform support

| Platform          | Status                                                |
| ----------------- | ----------------------------------------------------- |
| Linux             | Supported                                             |
| macOS             | Supported with tmux >= 3.3 and bash >= 3.2            |
| WSL2              | Supported (works as Linux; a dash `/bin/sh` is fine)  |
| Native Windows    | Not supported (tmux does not exist there)             |
| MSYS2 / Cygwin    | Not supported                                         |

The popup title flag (`display-popup -T`) is why the floor is tmux 3.3;
on tmux 3.2 the popup otherwise fails and the plugin reports a bare
"cancelled".

## Install with TPM

1. Add TPM if you don't have it yet:

```tmux
set -g @plugin 'tmux-plugins/tpm'
```

2. Add this plugin:

```tmux
set -g @plugin 'francjpd/broadmand'
```

3. Initialize TPM at the bottom of your `~/.config/tmux/tmux.conf`:

```tmux
run '~/.tmux/plugins/tpm/tpm'
```

4. Reload tmux config (`prefix r`) and press `prefix I` to fetch the plugin.

## Install (manual)

```sh
git clone git@github.com:francjpd/broadmand.git \
  ~/.tmux/plugins/broadmand
```

Add this to your `tmux.conf` and reload with `prefix r`:

```tmux
set -g @broadcast-run-key       'd'
set -g @broadcast-cd-picker-key 'D'
run-shell '~/.tmux/plugins/broadmand/broadmand.tmux'
```

## Install under Herdr

Inside [Herdr](https://herdr.dev), broadmand ships a `herdr-plugin.toml`
manifest, so it can be installed and driven from Herdr instead of only from
`tmux.conf`. The manifest declares two popup pane entrypoints and two actions —
one for the free-form command broadcast, one for the modal `cd` picker — both
running the same `scripts/run-all.sh` and `scripts/cd-all.sh picker` scripts the
tmux path uses.

### Install from GitHub

```sh
herdr plugin install francjpd/broadmand
```

This clones the repo into Herdr-managed plugin storage, validates the manifest,
and registers the plugin. Afterwards the entrypoints are available from the
Herdr plugin UI, and the actions can be bound to keys (below).

### Install from a local checkout

While developing, link the working tree instead of installing from GitHub:

```sh
herdr plugin link /path/to/broadmand
```

Commands run with the plugin directory as their working directory, so the
manifest calls the scripts by paths relative to the plugin root; the same
manifest works from either install shape.

### Keybindings

Herdr reaches plugin actions through `type = "plugin_action"` keybindings. Add
these to `~/.config/herdr/config.toml` and reload the config:

```toml
[[keys.command]]
key = "prefix+d"
type = "plugin_action"
command = "broadmand.broadcast"

[[keys.command]]
key = "prefix+shift+d"
type = "plugin_action"
command = "broadmand.cd-picker"
```

`prefix+d` / `prefix+shift+d` mirror broadmand's tmux `prefix d` / `prefix D`.
Change the keys if either is already bound (for example to detach in a
tmux-style config). The action ids are the manifest's `[[actions]]` ids,
qualified with the plugin id (`broadmand.<id>`).

Without keybindings, the same actions are reachable from the CLI —
`herdr plugin action invoke broadmand.broadcast` (or `broadmand.cd-picker`) —
and the popup panes with
`herdr plugin pane open --plugin broadmand --entrypoint broadcast` (or
`cd-picker`).

### Plain manual route

No plugin install is required. Clone the repo anywhere and call the two scripts
directly from inside a Herdr pane:

```sh
git clone git@github.com:francjpd/broadmand.git
/path/to/broadmand/scripts/run-all.sh        # free-form broadcast
/path/to/broadmand/scripts/cd-all.sh picker  # cd picker
```

### What differs from tmux

- There is no `tmux.conf` and no `@broadcast-*` options under Herdr; the
  configuration values (`@broadcast-excluded`, `@broadcast-picker-engine`,
  `@broadcast-pane-delay`) fall back to their built-in defaults.
- The interactive popups are Herdr plugin panes (`placement = "popup"`), opened
  through the plugin UI, `herdr plugin pane open`, or a `plugin_action`
  keybinding — not tmux `display-popup`.
- Discovery: the [Herdr marketplace](https://herdr.dev/plugins/) lists public
  GitHub repositories carrying the `herdr-plugin` topic on their default
  branch; this repository is tagged, so `herdr plugin install
  francjpd/broadmand` is also discoverable there.

## Configuration

| Option                          | Default                                          | Description                                  |
| ------------------------------- | ------------------------------------------------ | -------------------------------------------- |
| `@broadcast-run-key`            | `d`                                              | Prefix key for free-form command broadcast   |
| `@broadcast-cd-picker-key`      | `D`                                              | Prefix key for picker `cd`                   |
| `@broadcast-picker-engine`      | `fd`                                             | `fd`, `zoxide`, or `both`                    |
| `@broadcast-excluded`           | `vim,vi,nvim,less,man,ssh,htop,top,mc,opencode,claude,aider,continue,qwen,qwen-cli,gemini,gemini-cli,openai,ollama,copilot,codeium,anthropic,chatgpt,chatgpt-cli,sgpt,aichat,pplx,perplexity` | Comma-separated commands to skip; whitespace around entries is allowed |
| `@broadcast-pane-delay`         | `5`                                              | Milliseconds between `send-keys` ops         |

See [`examples/tmux.conf.snippet`](examples/tmux.conf.snippet) for a
drop-in config block.

## How it works

1. `run-all.sh` / `cd-all.sh` opens a tmux popup via `display-popup -E`,
   capturing stdout (under Herdr, `popup.sh` / `picker.sh` run inline in the
   pane instead). `run-all.sh` launches the popup from the active
   pane's cwd so that `Tab` completes relative paths as expected.
2. Inside the popup, `popup.sh` (the primitive) runs `read -e` to gather
   input, configured with a custom `INPUTRC` that enables zsh-style
   `menu-complete` cycling and immediate list display.
3. On submit, `cd-all.sh` expands a leading `~` and invokes
   `broadcast.sh "cd <path>"` while `run-all.sh` invokes
   `broadcast.sh "<command>"`.
4. `broadcast.sh` walks all panes in the active window, skipping excluded
   commands and panes in copy mode, and sends `C-u` + literal line +
   `Enter` to each.
5. `broadcast.sh` finishes by showing `broadmand: sent=N skipped=N` in the
   tmux status line with `display-message`, because `run-shell` discards
   stderr. `--dry-run` prints the same summary to stdout for testing.

## Testing

The suite needs only `bash` and `tmux`; `fzf`, `fd`, and `zoxide` are
stubbed where needed so it stays deterministic. It uses an isolated
`HOME` and `TMPDIR`.

```sh
bash tests/run.sh
```

It runs `bash -n` on every shell file (plus ShellCheck when installed),
the `util.sh` helper unit tests, a headless-tmux integration test for
loading, keybindings and broadcast skip logic, the broadcast-count
regression, a pty-driven popup test, the picker preview check, the
picker-stream test, and a Herdr test that drives the Herdr broadcast and
picker paths against a fake `herdr` on `PATH` (CI has no Herdr server).
`.github/workflows/ci.yml` runs the suite on Linux and on macOS (bash 3.2 +
BSD `ls`).

## License

MIT.
