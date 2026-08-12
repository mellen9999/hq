# hq

[![ci](https://github.com/mellen9999/hq/actions/workflows/ci.yml/badge.svg)](https://github.com/mellen9999/hq/actions/workflows/ci.yml)

running several claude code sessions in tmux? tmux already shows you the
sessions. what it can't tell you is **which one is blocked waiting on you**
and **which one is about to run out of context**.

hq is one status-line segment for exactly that, plus a runner for headless
claude workers. no session to attach to, no window of yours gets touched.

```
[0]   ◐ auth-token-fix  ●2  91%          ← your normal status line
```

a claude is stuck on a permission prompt (its task name), two are working,
one is at 91% context. nothing running → the segment is empty and your bar
looks exactly like it did before.

## install

```
git clone https://github.com/mellen9999/hq && cd hq && make install
hq hooks          # prints the claude code hooks that power the states
```

then in `~/.tmux.conf`:

```tmux
set -g status-left "[#S]   #($HOME/.local/bin/hq bar)"
set -g status-left-length 60
```

requires tmux, bash 5, claude code on PATH.

## what it costs

one tmux call plus a few file reads, ~8ms, run on your status-interval.
the context figure needs a transcript scan so it's cached for
`HQ_BAR_TTL` (60s) rather than recomputed every tick.

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
list. output tees to both the window and a log in
`~/.local/state/hq/<name>/runs/`, each with a `# resume:` line so you can
reopen the session. a stuck run is reaped after `REAP_S` (45min default):
process group first, then window, and only windows matching that robot's
own prefix.

**pin the model in `CLAUDE_ARGS`.** a robot with no `--model` inherits
whatever your interactive default happens to be — change it, or hit that
model's usage limit, and your unattended runs start failing with a
one-line error and nothing else to show for it.

## config

`~/.config/hq/hqrc` (sourced bash), all optional:

```
HQ_CTX      ctx window for unknown models   (default 200000)
HQ_BAR_TTL  status-bar ctx cache seconds    (default 60)
HQ_SESSION  name root; robots live in <name>x (default hq)
HQ_REAP_S   robot reap age seconds          (default 2700)
```

`hq kill` removes the robot session. your own claudes are never touched by
anything here.

## design notes

tmux and claude-transcript traps this walks around, for the next person:

- **`display -p '#(cmd)'` never runs the job** — `#()` only executes in
  real status-line rendering, so it always looks broken when you test it
  that way. verify by a side effect (a file the command touches) instead.
- **a `#()` job needs a trailing newline** — tmux reads job output
  line-wise, so `printf '%s'` with no `\n` shows up as nothing.
- **`pane_current_command` reports the wrapper shell**, not the child, so
  a claude behind `claude; exec bash` reads as `bash` — the pane title's
  spinner glyph is the reliable tell.
- **`unlink-window -t @22` unlinks from whichever session tmux resolves
  first**, not the one you meant. always name it: `unlink-window -t
  hqx:@22`.
- **killing a robot window orphans the tree** — kill-window's HUP only
  reaches the shell, which defers its trap while claude runs. TERM the
  pane's process *group* first, then kill the window.
- **`ps -o etimes=` for pane age** — tmux has no pane-creation-time
  format, and an empty format var reads as 0 in arithmetic, which would
  reap everything.
- **argless grep eats your loop** — `grep $(ls ...)` with no matches reads
  the enclosing while-read's stdin and silently swallows the rest.
- **context math**: sum exactly `input_tokens` +
  `cache_creation_input_tokens` + `cache_read_input_tokens` from the last
  non-sidechain usage block. summing every `*_tokens` field double-counts
  via `output_tokens` and the nested `cache_creation.ephemeral_*` object,
  and sidechain (subagent) turns report a tiny context that isn't the
  session's.

## history

this started as a full-screen board in its own tmux session, with tabs, a
nested viewer and live previews. it was more interesting to build than to
use: everything it showed, tmux already showed, and the parts it added
cost a session switch to reach. the useful residue was one line of status
bar. that's what's left.
