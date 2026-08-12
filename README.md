# hq

[![ci](https://github.com/mellen9999/hq/actions/workflows/ci.yml/badge.svg)](https://github.com/mellen9999/hq/actions/workflows/ci.yml)

running several claude code sessions in tmux? you can already see them —
what you can't see is **which one is blocked waiting for you**, and how
close each is to its context limit. hq puts that in the status line you
already look at, and a popup board one keystroke away.

no extra tmux session, nothing to attach to or detach from, no window of
yours gets moved.

```
[0]   ◐ auth-token-fix  ●2  91%          ← your normal status line
```

a claude is blocked on you (its task name), two are working, and one is at
91% context. when nothing is running the segment is empty and your bar
looks exactly like it did before.

`C-b h` opens the board over whatever you're doing:

```
hq 04:12:07Z   4 claudes

 1 ◐ 12m opus5     44% auth-token-fix
 2 ●  3s opus5     91% lossless-chat-archive
 3 ○  4h haiku45    8% waydroid setup
 4 ●  44s opus5     23% fix-083808

robot runs
     0 3m12s prod alert: healthcheck 500s — fixed, verified
  live 1m04s bug triage: image upload

 j/k pick · enter jump · n new · q close · ? keys
```

enter takes you to that claude in your own tmux and closes the popup.

## install

```
git clone https://github.com/mellen9999/hq && cd hq && make install
hq hooks          # prints the claude code hooks that power the states
```

then add to `~/.tmux.conf`:

```tmux
set -g status-left "[#S]   #($HOME/.local/bin/hq bar)"
set -g status-left-length 60
bind h run-shell -b "$HOME/.local/bin/hq popup"
```

requires tmux >= 3.2 (popups), bash 5, claude code on PATH.

## what the columns mean

`state · age · model · context · task`

- **● working / ◐ waiting / ○ done** — event-driven, from claude code
  hooks (`hq hooks`). ◐ is the one that matters: that session is sitting
  on a permission prompt burning your time. the age next to it is how long
  it's been stuck. without hooks everything else still works, you just get
  no states.
- **context** — input + cache tokens of the session's last turn as a % of
  that model's window (1M for opus/sonnet/fable-class, 200k haiku, else
  `HQ_CTX`). green under 50, yellow under 80, red above — red means
  compact it.
- **task** — claude's own title for what it's doing, so you can tell two
  sessions in the same repo apart.

the bar is cheap on purpose: one tmux call plus a few file reads, ~8ms,
with the context scan cached for `HQ_BAR_TTL` (60s) so it isn't re-read
every tick.

## robots

headless claude workers on a timer — a spooled prod alert, a bug report,
anything with a check. drop a config in `~/.config/hq/robots/<name>.sh`
(see `robots/example.sh`): a window-name prefix, claude flags, and a
`check()` that prints a prompt when there's work.

```
hq-poll <name>      run one poll
hq-poll -t <name>   generate + enable a systemd user timer
```

runs live in their own detached session so they never clutter your window
list; the board lists them and `enter` takes you to one mid-run. output
tees to both the window and a log in `~/.local/state/hq/<name>/runs/`, each
with a `# resume:` line. a stuck run is reaped after `REAP_S` (45min
default): process group first, then window, and only windows matching that
robot's own prefix.

**pin the model in `CLAUDE_ARGS`.** a robot with no `--model` inherits
whatever your interactive default happens to be — change it, or hit that
model's usage limit, and your unattended runs start failing with a
one-line error and nothing else to show for it.

## config

`~/.config/hq/hqrc` (sourced bash), all optional:

```
HQ_DIR      cwd for new claude tabs         (default $HOME)
HQ_CMD      command for new tabs            (default claude)
HQ_TICK     board refresh seconds           (default 2)
HQ_CTX      ctx window for unknown models   (default 200000)
HQ_BAR_TTL  status-bar ctx cache seconds    (default 60)
HQ_SESSION  name root; robots live in <name>x (default hq)
HQ_REAP_S   robot reap age seconds          (default 2700)
```

`hq kill` removes the robot session. your own claudes are never touched by
anything here.

## design notes

tmux traps this walks around, for the next person:

- **`unlink-window -t @22` unlinks from whichever session tmux resolves
  first** — not the one you meant. always name it: `unlink-window -t
  hqx:@22`. getting this wrong yanks windows out of the user's own
  session. (tmux refuses to unlink a window's last link, which is the
  safety net you want.)
- **`display -p '#(cmd)'` never runs the job** — `#()` only executes in
  real status-line rendering, so it always looks broken when you test it
  that way. verify by a side effect (a file the command touches) instead.
- **a `#()` job needs a trailing newline** — tmux reads job output
  line-wise, so `printf '%s'` with no `\n` shows up as nothing.
- **`window-size latest` silently ignores aggressive-resize** — a window
  shared across sessions keeps the biggest client's size and small
  viewers see it clipped. `smallest` + `aggressive-resize on` is the
  working combo.
- **killing a robot window orphans the tree** — kill-window's HUP only
  reaches the shell, which defers its trap while claude runs. TERM the
  pane's process *group* first, then kill the window.
- **`ps -o etimes=` for pane age** — tmux has no pane-creation-time
  format, and an empty format var reads as 0 in arithmetic, which would
  reap everything.
- **`pane_current_command` reports the wrapper shell**, not the child, so
  a claude behind `claude; exec bash` reads as `bash` — the pane title's
  spinner glyph is the reliable tell.
- **argless grep eats your loop** — `grep $(ls ...)` with no matches reads
  the enclosing while-read's stdin and silently swallows the rest.
- **context math**: sum exactly `input_tokens` +
  `cache_creation_input_tokens` + `cache_read_input_tokens` from the last
  non-sidechain usage block. summing every `*_tokens` field double-counts
  via `output_tokens` and the nested `cache_creation.ephemeral_*` object,
  and sidechain (subagent) turns report a tiny context that isn't the
  session's.
