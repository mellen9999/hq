# hq

mission control for claude code in tmux. every running claude — yours and
robot ones — is a tab in a left column. j/k to move, enter to type. pure
bash + tmux, no frameworks, no deps.

```
┌────────────┬──────────────────────────┐
│ hq  17:42Z │                          │
│            │                          │
│ tabs       │   the selected claude,   │
│  1 ● main  │   live and interactive   │
│  2 ◐ fix-… │                          │
│  3   dev:2 │                          │
│            │                          │
│ runs       │                          │
│ poll       │                          │
└────────────┴──────────────────────────┘
```

## install

```
git clone https://github.com/mellen9999/hq && cd hq && make install
```

requires tmux >= 3.1, bash, claude code on PATH. linux (systemd timers are
optional — cron works too).

## use

```
hq
```

builds two tmux sessions — `hq` (board + viewer) and `hqx` (one window per
claude) — and attaches. safe to re-run; re-attaches and heals missing panes.

keys (board pane):

```
j/k       move (selection previews live on the right)
gg G 1-9  top / bottom / jump
enter, l  put the cursor in the selected claude
n         new claude tab
x         kill selected robot (asks y/N; robots only)
r         refresh
q         detach
?         help
```

`C-b o` hops back from the claude to the board. `C-b C-b` reaches the inner
session's prefix when you want its scrollback.

claudes running in other tmux sessions show up as dim `ext` tabs — enter
switches the client to them.

## robots

headless claude workers on a timer. drop a config in
`~/.config/hq/robots/<name>.sh` (see `robots/example.sh`): a window-name
prefix, claude flags, and a `check()` that prints a prompt when there is
work. then:

```
hq-poll <name>      run one poll
hq-poll -t <name>   generate + enable a systemd user timer
```

runs appear as live tabs, exit on completion, and persist their output in
`~/.local/state/hq/<name>/runs/` (each log has a `# resume:` line). stuck
runs are reaped after `REAP_S` (default 45min) — process group first, then
window, and only windows matching the robot's own prefix.

## status glyphs

optional: `hq hooks` prints a claude code hooks snippet. with it wired,
tabs show ● working / ◐ waiting (bold — the one that matters) / ○ done,
and a robot stuck waiting on input fires a desktop notification.

## config

`~/.config/hq/hqrc` (sourced bash), all optional:

```
HQ_DIR      cwd for new claude tabs        (default $HOME)
HQ_CMD      command for new tabs           (default claude)
HQ_WIDTH    board pane width               (default 46)
HQ_TICK     board refresh seconds          (default 2)
HQ_SESSION  outer session name             (default hq; inner = <name>x)
HQ_REAP_S   robot reap age seconds         (default 2700)
```
