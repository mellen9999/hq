# hq

[![ci](https://github.com/mellen9999/hq/actions/workflows/ci.yml/badge.svg)](https://github.com/mellen9999/hq/actions/workflows/ci.yml)

running several claude code sessions in tmux? tmux already shows you the
sessions. what it can't tell you is **which one is blocked waiting on you**
and **which one is about to run out of context**.

hq answers both in the tab bar you already read — nothing to open, nothing
to attach to, no window of yours gets touched.

```
[0]   1:mpv  2:claude  3:claude*                     91%
                ↑         ↑                           ↑
            yellow:    green:                    someone is nearly
          waiting on   working                   out of context
             you
```

your tabs are coloured by what each claude is doing, the instant it
changes. nothing running → your bar looks exactly like it always did.

## install

```
git clone https://github.com/mellen9999/hq && cd hq && make install
hq hooks          # prints both bits of config to paste
```

`hq hooks` gives you the claude code hooks (they paint the tabs) and the
three tmux lines that render them. requires tmux, bash 5, claude code on
PATH.

## how it works

the hooks fire on state changes and set that window's own
`window-status-style`, plus an `@hqstate` option other tools can read. no
polling, no daemon — the tab is already the right colour by the time you
look at it. the style has to live on the window rather than in a
`window-status-format` conditional: user options expand to empty while the
status line renders, so a format that reads `@hqstate` paints nothing. the hook
does nothing at all when the state hasn't moved, which matters because
`PreToolUse` runs on every single tool call.

the one thing that can't be event-driven is context, since it lives in the
session transcript. `hq bar` computes it on your status-interval (~8ms, one
tmux call plus a few reads, cached for `HQ_BAR_TTL`) and prints a red
percentage only past 80. it also fixes up any tab whose claude died without
firing `SessionEnd`, so a crashed session can't leave a colour behind.

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
