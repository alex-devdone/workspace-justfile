# One entry point for a workspace of sibling TypeScript repos.
#
# Expected layout — this file sits at the workspace root, next to the repos and
# next to their git worktrees:
#
#   workspace/
#     justfile             <- you are here
#     api/                 TypeScript HTTP service    `just api`       :8080
#     api-wt-search/       git worktree of api/       `just api 8081`  :8081
#     worker/              TypeScript queue worker    `just worker`    :8085
#     worker-wt-retries/   git worktree of worker/    `just worker 8086`
#     web/                 Vite + React frontend      `just web`       :3000
#
# Every recipe runs from the workspace root, from the repo, or from any worktree
# of it — `cd api-wt-search && just api 8081` starts *that* checkout on its own
# port, alongside the one running from api/. Create worktrees with `just wt`.
#
# The repos are yours to supply. A runnable version of this layout — three
# stand-in services and this file, imported unchanged — is in
# examples/workspace/; every pattern below is explained in README.md.

# Bare `just` lists recipes instead of running the first one in the file.
default:
    @just --list

root := justfile_directory()

# Package manager every service is started with. `PM=npm just api` to override.
pm := env_var_or_default("PM", "pnpm")

# --- services ---------------------------------------------------------------
# Each public recipe is a name plus a set of arguments. The mechanics live once
# in `_node`; `just --list` reads as documentation of what can be run.
#
# Every one of them takes a port, so the same recipe run from a worktree can
# come up next to the one already running from the main checkout.

# HTTP service.
api port="8080": (kill-port port) (_node "api" port)

# Queue worker. A second instance alongside the first: `just worker 8086`.
worker port="8085": (kill-port port) (_node "worker" port)

# Frontend.
web port="3000": (kill-port port) (_node "web" port)

# --- worktrees --------------------------------------------------------------

# Add a worktree of <repo> at <repo>-wt-<name>, ready to run.
wt repo name start="HEAD":
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{ root }}/{{ repo }}"
    dst="{{ root }}/{{ repo }}-wt-{{ name }}"
    [[ -d "$src" ]] || { echo "[just wt] no such repo: $src"; exit 1; }
    # The <repo>-wt-<name> path is not decoration: recipes find a checkout by
    # prefix-matching the repo name, so a worktree parked anywhere else, or
    # named anything else, will not resolve.
    git -C "$src" worktree add "$dst" -b "{{ name }}" "{{ start }}"
    echo "[just wt] ready:  cd $dst && just {{ repo }} <port>"

# Every worktree of every repo in the workspace.
wt-list:
    #!/usr/bin/env bash
    for repo in {{ root }}/*/.git; do
        dir="$(dirname "$repo")"
        [[ -d "$repo" ]] || continue          # a worktree's .git is a file, skip those
        echo "$(basename "$dir"):"
        git -C "$dir" worktree list | sed 's/^/  /'
    done

# Args pass straight through, so one recipe covers the whole compose surface:
# `just stack`, `just stack ps`, `just stack down -v`. Expects a stack/ directory
# with your own compose file — there isn't one in examples/workspace.

# Local dependencies (postgres, redis).
stack *args="up -d --wait":
    @cd {{ root }}/stack && docker compose {{ args }}

# Follow the deps' logs, optionally one service: `just stack-logs postgres`.
stack-logs *args:
    @cd {{ root }}/stack && docker compose logs -f {{ args }}

# --- the machinery ----------------------------------------------------------

# dir:  repo directory name, also the log name
# port: passed through to the dev script as `--port`
_node dir port:
    #!/usr/bin/env bash
    # pipefail matters below: `cmd | tee` otherwise reports tee's exit code, so a
    # service that died on startup looks like a clean run.
    set -euo pipefail

    # Run from anywhere. Walking up from where you were standing means any
    # directory inside the repo — or inside a worktree of it, api-wt-search/ —
    # resolves to *that* checkout, so `cd api-wt-search && just api 8081` runs
    # the worktree's code and never the main one. Prefix match, because a
    # worktree is named after the repo it came from.
    from="{{ invocation_directory() }}"
    target=""
    d="$from"
    while [[ "$d" != "/" ]]; do
        if [[ -f "$d/package.json" && "$(basename "$d")" == {{ dir }}* ]]; then
            target="$d"
            break
        fi
        d="$(dirname "$d")"
    done
    # Standing anywhere else — the workspace root, or another repo entirely —
    # falls back to the main checkout next to this justfile. So `just worker`
    # works from inside api-wt-search/ too.
    if [[ -z "$target" && -d "{{ root }}/{{ dir }}" ]]; then
        target="{{ root }}/{{ dir }}"
    fi
    # Say what to do, not just what is wrong.
    if [[ -z "$target" ]]; then
        echo "[just {{ dir }}] no {{ dir }} checkout here or at {{ root }}/{{ dir }}"
        echo "[just {{ dir }}] fix: clone it next to this justfile, or run from inside it"
        exit 1
    fi
    cd "$target"

    [[ -d node_modules ]] || {{ pm }} install

    # Mirroring to a fixed path lets another terminal or tool read the run
    # without competing for the scrollback. Named after the *checkout*, not the
    # repo, so a worktree's run doesn't overwrite the main one's log.
    log="/tmp/$(basename "$PWD").log"
    echo "[just {{ dir }}] $(basename "$PWD") on :{{ port }} — streaming to $log"
    {{ pm }} run dev -- --port {{ port }} 2>&1 | tee "$log"

# Free a port, unless the thing holding it is something you'd regret killing.
kill-port port="3000":
    #!/usr/bin/env bash
    # LISTEN only: a bare `lsof -ti:PORT` also matches *client* sockets that
    # merely connect to it, including dead ones stuck in CLOSED — stale outbound
    # connections made ports look occupied when nothing was serving on them.
    pids=$(lsof -tiTCP:{{ port }} -sTCP:LISTEN 2>/dev/null || true)
    if [[ -z "$pids" ]]; then
        echo "Port {{ port }} is free"
        exit 0
    fi

    # lsof can return several PIDs; `ps -p` accepts only one, so ask per PID. A
    # multi-PID variable makes ps fail, the name fall back to "unknown", and
    # every guard below silently miss.
    #
    # Two passes on purpose: check everything before killing anything, so a
    # protected process on the port can't be reached by killing its neighbour.
    for pid in $pids; do
        name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")

        # Docker publishes container ports through its own backend process.
        # kill -9 on that takes down the daemon and every container with it.
        if [[ "$name" == *com.docker.backend* ]]; then
            echo "Port {{ port }} is held by Docker (a published container port), not a host process."
            echo "Stop the container instead:  just stack down"
            exit 1
        fi

        # An ssh LocalForward listens on the port too, and kill -9 drops the
        # whole session — every shell and tmux pane inside it — not the forward.
        # Whether the forward still leads anywhere is not knowable from out here
        # (ssh accepts the connection before it finds out), so this refuses and
        # hands you the two facts that decide it: what the process is, and
        # whether you're sitting in it.
        if [[ "$name" == "ssh" || "$name" == */ssh ]]; then
            echo "Port {{ port }} is an ssh port-forward (PID: $pid), not a local service."
            ps -p "$pid" -o args= 2>/dev/null | cut -c1-100 | sed 's/^/  /'
            if [[ "$(ps -p "$pid" -o tty= 2>/dev/null | tr -d ' ')" == "??" ]]; then
                # No controlling terminal: a background tunnel (`ssh -f -N -L`)
                # or a tool's transport. There is no session to leave.
                echo "No terminal attached — a background forward, not a session you're in."
                echo "If you don't need it:  kill $pid"
            else
                echo "It comes from a LocalForward in ~/.ssh/config — exit that ssh session,"
                echo "or drop just this forward, then re-run."
            fi
            exit 1
        fi
    done

    for pid in $pids; do
        name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
        echo "Port {{ port }} is occupied by '$name' (PID: $pid), killing..."
        kill -9 "$pid"
    done

# The docker and ssh guards are deliberately not exercised live: a broken guard
# would take down the very thing the test would have to put in its way.

# Check kill-port — the one piece here that has to be correct on its own.
selftest:
    #!/usr/bin/env bash
    set -euo pipefail
    port=18080

    just kill-port $port >/dev/null
    node -e "require('http').createServer().listen($port, '127.0.0.1')" &
    trap 'kill %1 2>/dev/null || true' EXIT

    for _ in $(seq 25); do
        lsof -tiTCP:$port -sTCP:LISTEN >/dev/null 2>&1 && break
        sleep 0.2
    done
    lsof -tiTCP:$port -sTCP:LISTEN >/dev/null 2>&1 || { echo "FAIL: listener never came up"; exit 1; }

    just kill-port $port
    sleep 0.5
    if lsof -tiTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
        echo "FAIL: port $port still held after kill-port"
        exit 1
    fi

    just kill-port $port | grep -q "is free" || { echo "FAIL: free port not reported free"; exit 1; }
    echo "PASS: kill-port reclaims a held port and no-ops on a free one"
