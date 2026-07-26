# A workspace you can run

Three stand-in services and the repo's `justfile`, imported unchanged:

```
examples/workspace/
  justfile             import '../../justfile'
  api/                 HTTP service     just api      :8080
  worker/              queue worker     just worker   :8085
  web/                 frontend         just web      :3000
```

The services are zero-dependency Node scripts standing in for real TypeScript
ones, so this runs offline. Each reports the checkout it was started from —
which is what makes the worktree behaviour visible rather than theoretical.

## Run it

Start it **from the service folder**, not the root — that's where you already
are when you're working on it:

```bash
cd examples/workspace/api
just api
curl 127.0.0.1:8080
```

```json
{
  "service": "api",
  "checkout": "api",
  "port": 8080
}
```

There is no justfile in `api/`, and none is needed. Two separate walks make that
work: `just` itself walks up from your shell to find the nearest justfile
(`examples/workspace/justfile`), and then the recipe walks up from
`invocation_directory()` to find the checkout you're standing in. The same
command means the same thing everywhere:

| Run `just api` from | Starts |
|---|---|
| `examples/workspace` | `api/` — the fallback next to the justfile |
| `examples/workspace/api` | `api/` |
| `examples/workspace/api/src` | `api/` |
| `examples/workspace/api-wt-search/src` | `api-wt-search/` — the worktree |
| `examples/workspace/worker` | `api/` — the fallback again; you aren't inside an api checkout |

`just` on its own lists everything, from any of those directories. `just worker`
and `just web` work the same way.

Not on pnpm? Every recipe honours `PM`:

```bash
PM=npm just api
```

## The worktree walkthrough

This is the part worth trying. Make `api/` a real repo first — it can't ship as
one, since a nested `.git` would turn it into a submodule of this repo:

```bash
cd examples/workspace/api
git init && git add -A && git commit -m "api stand-in"
cd ..
just wt api search      # worktree at api-wt-search/, on branch `search`
just wt-list
```

The `<repo>-wt-<name>` path is what `just wt` is for: resolution finds a checkout
by prefix-matching the repo name, so a worktree parked anywhere else won't be
found.

Now run both, from anywhere inside either one:

```bash
just api                                # main checkout  → :8080
cd api-wt-search/src && just api 8081   # the branch     → :8081
```

```console
$ curl 127.0.0.1:8080 | jq -c '{checkout, port}'
{"checkout":"api","port":8080}

$ curl 127.0.0.1:8081 | jq -c '{checkout, port}'
{"checkout":"api-wt-search","port":8081}
```

Two checkouts, two ports, two logs — `/tmp/api.log` and
`/tmp/api-wt-search.log`. The second command was run from `api-wt-search/src`,
not the worktree root, and still resolved to the right checkout.

### Leave the port off and it's a hand-off

The port argument is what makes them coexist. Without one, every `just api`
wants the same default:

```bash
just api                            # main checkout → :8080
cd api-wt-search && just api        # no port → also :8080
```

```console
Port 8080 is occupied by '…/node' (PID: 87960), killing...

$ curl 127.0.0.1:8080 | jq -c '{checkout, port}'
{"checkout":"api-wt-search","port":8080}
```

The worktree took :8080 off the main checkout, because `kill-port` cleared it
first — working exactly as designed, and usually what you want when you switch
which branch you're testing. The last `just api` wins the default port; pass one
when you'd rather have both.

Tear it down with `git -C api worktree remove ../api-wt-search`.

## Not included

`just stack` expects a `stack/` directory with a compose file for your
dependencies. There isn't one here — the stand-in services don't connect to
anything.
