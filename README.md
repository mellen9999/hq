# hq

[![ci](https://github.com/mellen9999/hq/actions/workflows/ci.yml/badge.svg)](https://github.com/mellen9999/hq/actions/workflows/ci.yml)

mission control for claude code in tmux. every running claude — yours and
robot ones — is a tab in a left column. j/k to move, enter to type. pure
bash + tmux, no frameworks, no deps, ~6 forks per idle tick.

```
hq 02:27:48Z 1.10 9/30G
tabs
 1 ●  2s fable5    55% refactor-auth-module
 2 ◐12m opus5     93% fix-175645
 3 ○ 4h haiku45    8% set up waydroid
runs
     0 3m12s fix-175645 healthcheck: verified prod
  live 1m04s tri-190944 triage: image upload 500s
poll
  ins 14m spawning instafix fix-175645 ▸2m
```

## install

```
git clone https://github.com/mellen9999/hq && cd hq && make install
```

requires tmux >= 3.1, bash 5, claude code on PATH. linux (systemd timers
are optional — cron works too).

## use

```
hq
```

builds two tmux sessions — `hq` (board + viewer) and `hqx` (one window per
claude) — and attaches. safe to re-run; re-attaches and heals missing
panes. claudes running in other tmux sessions are adopted as live tabs
(window links — same window, so you watch AND type, from any client);
their home sessions keep them, and when a claude exits the tab is handed
back. `HQ_LINK=0` keeps hq to its own claudes only.

## board anatomy

each tab row: number · state glyph · age · model · context meter · task.

- **● working / ◐ waiting / ○ done** — event-driven via claude code hooks
  (`hq hooks` prints the snippet; optional — no hooks, no glyphs). ◐ is
  the one that matters: a claude blocked on a permission prompt. its age
  is the staleness alarm. a *robot* stuck waiting also fires a desktop
  notification.
- **context meter** — input + cache tokens of the session's last turn as
  a % of the model's window (1M for opus/sonnet/fable-class, 200k haiku,
  `HQ_CTX` for unknowns). green <50, yellow <80, red above: time to
  `/compact`.
- **runs** — robot history: exit code (yellow `live` while running),
  duration, first prompt line.
- **poll** — per robot: last poller message, its age, and `▸` time to
  next timer fire.
- header carries the host: loadavg and used/total memory.

everything is mtime-gated: transcripts and logs are re-read only when
they change, so an idle board costs a handful of tmux calls and one
batched stat per tick — no grep, no awk, no tail.

## keys

the cursor lives in the claude input — just type. these work from anywhere
in the hq session, typing included (alt keys, scoped to hq only):

```
M-j M-k   next / previous tab — and arm nav mode
M-Space   arm nav mode without moving
M-1..9    jump to tab
M-n       new claude tab
M-h M-l   hop board <-> input
```

nav mode is a sticky layer (vim normal, one level up): after M-j/M-k or
M-Space, bare `j k g G 1-9 n h` act on tabs — no modifier held. the first
other key (vim habit: `i`) drops you back to typing; the board header
shows `nav` while it's armed. claude's own esc/normal mode stays claude's.

board keys (after M-h):

```
j/k       move (selection previews live on the right)
gg G 1-9  top / bottom / jump
enter l i back to the input, cursor in the selected claude
n         new claude tab
x         kill selected robot (asks y/N; robots only)
r         flush caches and rescan
q         detach
?         help
```

no alt on your keyboard (phones)? prefix works everywhere: `C-b j` /
`C-b k` switch tabs and arm nav mode, `C-b Space` arms it in place —
then bare `j k g G 1-9` as usual.

`HQ_BINDS=0` in hqrc removes all of it. `C-b C-b` reaches the inner
session's prefix when you want its scrollback.

## small screens

below `HQ_NARROW` columns (default 100) hq shows one full-screen pane at
a time instead of the split: the claude fills the screen, tab keys still
switch, and `C-b o` flips to the full-screen board and back. attach from
a phone and it just happens; back on a wide terminal it un-zooms itself.
`HQ_NARROW=0` forces the split everywhere.

## in / out / restart

hq lives on your existing tmux server — no second attach, no separate
terminal. your claudes stay in their own sessions; hq is a viewport over
all of them.

```
M-q          toggle: hq from anywhere <-> back where you were
             (no alt? C-b Tab does the same)
q  (board)   leave hq, back to your previous session
C-b d        detach from tmux entirely — everything keeps running
hq           from any shell: build if needed + enter
hq restart   rebuild board + viewer; claudes untouched
hq kill      remove hq's sessions. adopted claudes survive in their
             home sessions; hq-native tabs and live robot runs die
```

ctrl-c in the right pane goes to the claude you're looking at, not to hq.

## robots

headless claude workers on a timer. drop a config in
`~/.config/hq/robots/<name>.sh` (see `robots/example.sh`): a window-name
prefix, claude flags, and a `check()` that prints a prompt when there is
work. then:

```
hq-poll <name>      run one poll
hq-poll -t <name>   generate + enable a systemd user timer
```

runs appear as live tabs (output tees to the window and the log), exit on
completion, and persist in `~/.local/state/hq/<name>/runs/` — each log has
a `# resume:` line to reopen the session. stuck runs are reaped after
`REAP_S` (default 45min): process group first, then window, and only
windows matching the robot's own prefix.

## config

`~/.config/hq/hqrc` (sourced bash), all optional:

```
HQ_DIR      cwd for new claude tabs        (default $HOME)
HQ_CMD      command for new tabs           (default claude)
HQ_WIDTH    board pane width               (default 46)
HQ_TICK     board refresh seconds          (default 2)
HQ_NARROW   full-screen below this width   (default 100)
HQ_SESSION  outer session name             (default hq; inner = <name>x)
HQ_REAP_S   robot reap age seconds         (default 2700)
HQ_CTX      ctx window for unknown models  (default 200000)
HQ_BINDS    0 = no alt keys                (default 1)
HQ_LINK     0 = don't adopt other sessions (default 1)
```

## design notes

the tmux traps this thing walks around, for the next person:

- **nested viewer**: the right pane runs `env -u TMUX tmux attach` to the
  inner session in a respawn loop. the inner session gets
  `detach-on-destroy on` — otherwise a dying inner session drops its
  client into the outer session and you get hq inside hq, forever.
- **`set-option -t "=name"` fails silently**: set-option rejects tmux's
  exact-match `=` prefix (list/kill/select accept it). use `"name:"`.
- **killing a robot window orphans the tree**: kill-window's HUP only
  reaches the shell, which defers its trap while claude runs. TERM the
  pane's process *group* first, then kill the window.
- **`ps -o etimes=` for pane age**: tmux has no pane-creation-time
  format, and an empty format var reads as 0 in arithmetic — which would
  reap everything.
- **`pane_start_command` is stored quote-wrapped**, and
  `pane_current_command` reports the wrapper shell, not the child — shape
  detection must substring-match the start command.
- **pane commands don't inherit your env** — session names are baked into
  the command strings.
- **argless grep eats your loop**: `grep $(ls ...)` with no matches reads
  the enclosing while-read's stdin and silently swallows the rest of it.
- **`window-size latest` silently ignores aggressive-resize**: a window
  shared across sessions keeps the biggest client's size and small
  viewers see it clipped — the bottom of the claude UI (input + status)
  falls off a phone screen. `window-size smallest` + `aggressive-resize
  on` is the working combo: sized to the smallest viewer *actively
  looking at it*, so an idle big client elsewhere doesn't clamp it.
- **instant bar sync without polling**: a `set-hook after-select-window`
  on the inner session sends `C-l` to the board pane — the board's read
  loop treats it as a rescan poke.
- **the fork diet**: v2 board forked ~63 times per idle tick (per-tab
  transcript greps, per-row subshells). v3 keeps every cache in bash
  assoc arrays, batches all freshness checks into one `stat`, and re-reads
  a file only when its mtime moved: ~6 forks per idle tick, zero
  grep/awk/tail when nothing changed.
- **`read -t` returns >128 on timeout *and* on signals** — WINCH during
  the read is indistinguishable from a tick, which is fine: the next pass
  re-renders with fresh columns.
