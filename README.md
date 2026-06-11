# openresty-oidc

A patched, opinionated container image that wraps the upstream
[OpenResty](https://openresty.org/) Alpine image with
[`lua-resty-openidc`](https://github.com/zmartzone/lua-resty-openidc)
preinstalled, plus an unprivileged runtime user. Intended as a drop-in base
image for services that terminate OpenID Connect at an OpenResty/NGINX
reverse proxy.

The published image lives in Google Artifact Registry.

## Status: maintenance-mode only

This image exists to keep existing consumers patched and supported, not as
a long-term part of the platform. New services should not adopt it. The
direction of travel is to phase consumers off `openresty-oidc` and onto
the standard NGINX image, with OIDC/authentication handled by a different
mechanism (for example, a dedicated auth proxy, a sidecar, or platform-level
identity-aware ingress) depending on the consumer's needs.

## What this image provides

- The upstream `openresty/openresty:<version>-alpine` image as the base.
  Every NGINX patch shipped by OpenResty (including backported CVE fixes)
  is inherited automatically.
- `lua-resty-openidc` and its transitive dependencies (`lua-resty-session`,
  `lua-resty-http`, `lua-resty-jwt`, `cjson`) installed into OpenResty's
  LuaJIT tree at `/usr/local/openresty/luajit/share/lua/<lua-version>/`,
  so `require("resty.openidc")` works out of the box.
- A non-root runtime user (`openresty`, uid/gid 101) with ownership of
  the directories NGINX needs to write at startup (`logs/`, `conf/`,
  `/var/run/openresty/`).
- OpenResty's `resty` CLI (and its Perl dependency) preserved for ad-hoc
  debugging from a shell inside the container.

## Repository layout

| Path | What it does |
|---|---|
| `Dockerfile` | Image build recipe. All versions and metadata are `ARG`s. |
| `Makefile` | Single source of truth for versions and the image's registry path. |
| `.github/workflows/build.yml` | Builds and pushes to GAR on default-branch pushes and version tags. |
| `.github/workflows/pr-check.yml` | Builds and runs smoke tests on every pull request. Never pushes. |

## Prerequisites

- Docker (with `buildx`). Docker Desktop ≥ 4.x or Docker Engine ≥ 23.x
  ships with buildx enabled.
- GNU `make`.
- For pushing manually (rarely needed, since CI handles this): `gcloud` authed
  with permissions to push to the target Artifact Registry repo.

On macOS:

```sh
brew install docker make
# or use Docker Desktop / Colima for the daemon
```

On Debian/Ubuntu:

```sh
sudo apt install docker.io make docker-buildx
```

## Common commands

All driven by the `Makefile`. Override any variable on the command line
to experiment without editing the file.

```sh
make build         # build the image locally
make smoke-test    # run smoke tests against the built image
make print-image   # print the fully-qualified image name that build/push will use
make print-tag     # print just the image tag
make push          # push to GAR (CI does this; rarely needed locally)
make clean         # remove the locally-tagged image
```

Examples:

```sh
# Build for a different platform
make build PLATFORM=linux/arm64

# Build with a newer OpenResty release
make build OPENRESTY_VERSION=1.31.0.1

# Build pointed at a different registry (e.g. a personal sandbox)
make build REGISTRY=ghcr.io/my-user REPOSITORY=openresty-oidc-sandbox
```

## Contributing

### Workflow

1. Open a pull request against `main`.
2. The PR check workflow builds the image and runs the smoke tests. It
   must pass before merge.
3. After the PR is merged, the build workflow publishes the image to GAR
   under two tags:
   - `:<OPENRESTY_VERSION>-<BUILD_NUMBER>-<OPENRESTY_VARIANT>` (the
     canonical release tag, e.g. `:1.29.2.5-0-alpine`)
   - `:latest` (tip-of-trunk pointer)

### Tagging convention

The canonical tag follows the format the predecessor image used:

```
<OPENRESTY_VERSION>-<BUILD_NUMBER>-<OPENRESTY_VARIANT>
```

For example: `1.29.2.5-0-alpine`. All three components come from the
`Makefile` and the workflow assembles the tag automatically. Consumers
pin to a specific tag in their `values.yaml`.

When to bump what:

- **New upstream OpenResty release**: bump `OPENRESTY_VERSION` and reset
  `BUILD_NUMBER` to `0`. First build for `1.30.0.1` would tag as
  `1.30.0.1-0-alpine`.
- **Rebuild of the same upstream version** (Dockerfile change, openidc
  version bump, build-dependency update, anything that changes the
  resulting image without changing the upstream OpenResty release):
  keep `OPENRESTY_VERSION`, bump `BUILD_NUMBER` to `1`, `2`, etc. So a
  rebuild of `1.29.2.5-0-alpine` would publish as `1.29.2.5-1-alpine`.
- **Switch image variant**: change `OPENRESTY_VARIANT` (e.g. from
  `alpine` to something else, if we ever support another base).

Bump these in the same PR that introduces the change so the published
tag is meaningful. The PR check workflow runs the smoke tests against
the resulting image before merge; the publish step only runs after the
PR is merged.

### Updating versions

All version inputs live at the top of the `Makefile`:

```make
OPENRESTY_VERSION         ?= 1.29.2.5
OPENRESTY_VARIANT         ?= alpine
LUA_RESTY_OPENIDC_VERSION ?= 1.7.6
LUA_VERSION               ?= 5.1
BUILD_NUMBER              ?= 0
```

Open a PR that edits the relevant line(s) (and bumps `BUILD_NUMBER` when
appropriate per the table above), let CI confirm the smoke tests still
pass, then merge.

#### Identifying the right `OPENRESTY_VERSION`

The upstream image tag is `openresty/openresty:<OPENRESTY_VERSION>-<OPENRESTY_VARIANT>`.

- Releases:
  <https://openresty.org/en/changelog-1029002.html> (and adjacent
  changelog pages for older lines).
- DockerHub tag list:
  <https://hub.docker.com/r/openresty/openresty/tags>.
- For security-driven bumps, cross-check against the NGINX advisory
  list (<https://nginx.org/en/security_advisories.html>) and confirm
  OpenResty's changelog mentions the CVE backport before relying on it.

Tip: use a specific patch version (e.g. `1.29.2.5`), not a floating
minor. Pinning is the whole point.

#### Identifying the right `LUA_RESTY_OPENIDC_VERSION`

Available versions: <https://luarocks.org/modules/hanszandbelt/lua-resty-openidc>.

**Do not blindly bump to the latest version.** See
[Decision: lua-resty-openidc pin](#decision-lua-resty-openidc-pin) below
for the constraint we're holding.

#### Identifying the right `LUA_VERSION`

This is the Lua API version the build's `luarocks` targets, which
should be `5.1` to match OpenResty's bundled LuaJIT (5.1 ABI-compatible). It
should not change unless OpenResty itself moves off the 5.1 ABI, which
has not happened in any released version to date.

#### Identifying the right `OPENRESTY_VARIANT`

Today only `alpine` is supported. Switching to a different upstream
base (e.g. `bookworm`) would require revisiting the apk package names,
the runtime user setup, and the CA-certificate path that callers'
NGINX configs reference.

## Decisions

### Decision: lua-resty-openidc pin

`LUA_RESTY_OPENIDC_VERSION` is pinned to `1.7.6` rather than tracking
the latest available release. The reason: `lua-resty-openidc` 1.8.0
hard-requires `lua-resty-session` 4.x (per its rockspec
`lua-resty-session >= 4.0.3`), and `lua-resty-session` 4.x removed the
nginx-variable-based session configuration interface
(`set $session_storage redis;`, `set $session_redis_host ...`, etc.)
that was supported in the 2.x and 3.x lines. Downstream consumers of
this image are known to rely on that interface, so jumping to 1.8.0
would silently break session configuration at deploy time (sessions
would fall back to default cookie storage rather than the configured
backend).

The pin is intentionally tied to the previous baseline shipped by the
predecessor image so that this image is a drop-in replacement and the
roll-forward only changes what it needs to (the NGINX patch level).

Lifting this pin requires a coordinated migration of all downstream
NGINX configs to the `lua-resty-session` 4.x configuration model
(opts table passed to `openidc.authenticate(opts, _, _, session_opts)`).
That should be a deliberate, planned project, not a side effect of
a routine version bump.

### Decision: base image strategy

This image is built `FROM openresty/openresty:<version>-<variant>`
rather than compiling OpenResty/NGINX from source with `--with-patch=`
or similar. Inheriting the upstream patched image means:

- We pick up NGINX CVE backports as soon as OpenResty cuts a release
  containing them, with no manual patch management on our side.
- The image's nginx binary and configure flags exactly match
  upstream: same modules, same compile options, no maintenance drift.

The cost is a tighter coupling to OpenResty's release cadence: if a
CVE fix has not yet been backported into an OpenResty release, this
image cannot ship the fix either. In practice OpenResty backports
critical NGINX fixes within days.

### Decision: runtime user

The image runs as `openresty` (uid/gid 101) by default, matching the
runtime user the predecessor image declared. Consumers that explicitly
set `securityContext.runAsUser` in their Pod spec are unaffected; those
that rely on the image's default uid get the same behavior as before.

### Decision: parameterized image source

The registry path the image is published to lives at the top of the
`Makefile` as `REGISTRY` and `REPOSITORY`, and is also driven into the
image's OCI labels via `IMAGE_SOURCE`. This separates "where the image
is hosted" from "how the image is built" so the canonical home can be
moved without touching the `Dockerfile`.

## Smoke-test coverage

Both the PR check workflow and the release workflow run `make smoke-test`,
which verifies:

1. The bundled NGINX reports the expected OpenResty version (`nginx -V`).
2. The container's default runtime user is `openresty` (uid 101).
3. `lua-resty-openidc` is present in OpenResty's Lua tree and reports
   the expected `_VERSION`.
4. `resty.openidc`, `resty.session`, and `cjson` all `require` cleanly
   via OpenResty's `resty` CLI (i.e. no missing transitive dependencies).
5. The container starts under the default `CMD`, stays running, and
   stops cleanly on SIGQUIT.

These are intentionally narrow. They catch packaging regressions but
do not attempt to exercise end-to-end OIDC behavior. Functional OIDC
testing belongs in consumer integration tests, where a real IdP and a
realistic NGINX config are available.

## CI / publishing

Two workflows, defined in `.github/workflows/`:

- **`pr-check.yml`**: triggered on `pull_request` to `main`. Builds the
  image locally and runs the smoke tests. No registry credentials, no
  push.
- **`build.yml`**: triggered on push to `main` and on tags matching
  `vX.Y.Z[-rcN]`. Builds the image, runs the smoke tests, and pushes
  to GAR with the tag scheme described in [Workflow](#workflow) above.

Both pipelines pin every Action by commit SHA, matching the versions
in use elsewhere in the Mozilla GitHub org.
