# windows-docker

Spins up Windows 10 Pro in a container using [dockur/windows](https://github.com/dockur/windows), then runs a phased OEM setup that:

1. Permanently activates Windows (TSforge via [MAS](https://massgrave.dev/))
2. Installs and permanently activates Microsoft Office 2024 LTSC (Ohook)
3. Installs Git for Windows + Visual C++ Redistributable
4. Installs a configurable PHP version with extensions, plus Composer
5. Mirrors your project files into `C:\Projects` and runs your post-install hook

The headline feature: **redeploys re-use the activated Windows install.** Bumping the PHP version, editing extensions, or changing project code triggers only the affected phase — not a 30-minute Windows reinstall.

## Why phases?

The original layout ran everything inside a single `install.bat` that wrote a single `install.done` marker. Re-deploying meant either `make reset` (full 30-min reinstall) or accepting that the new config was ignored.

The current layout splits the work into three phases, each with its own marker on the VM disk:

| Phase | What it does | Re-runs when… |
|---|---|---|
| **`phase-base`** | Windows activation + Office + Git + VC++ Redist | Never (only on a wiped disk) |
| **`phase-php`** | Download + extract PHP, apply `php.ini`, install Composer | SHA-256 of `shared/.runtime/php-config.ini` differs from the stored hash |
| **`phase-code`** | Mirror `shared/` → `C:\Projects`, run `post-install.bat` | SHA-256 of `shared/.runtime/post-install.bat` differs from the stored hash |

Hashes and markers live in `C:\OEM-state\` on the VM disk. Logs live in `C:\OEM-logs\`.

### Boot-time dispatcher

dockur only fires `oem/install.bat` once during Windows OOBE. So `install.bat` does phase-base, then registers a Windows scheduled task — `OEM-Dispatcher` — that runs at every system startup. The task invokes `C:\OEM-bootstrap\boot-launcher.bat`, which:

1. Mirrors `\\host.lan\Data\.runtime\` (the orchestrator + your config files) into `C:\OEM-runtime`.
2. Runs `C:\OEM-runtime\dispatcher.bat`, which iterates the phases, hashes each phase's trigger input, and only invokes the phase script if the hash changed (or if the phase never ran, or if the previous run was interrupted).

Each phase writes a `.running` marker before starting and renames it to `.done` only on success. A pod that's killed mid-phase leaves the `.running` marker behind, which forces the phase to re-run on the next boot.

## Requirements

- Linux host with KVM enabled (`/dev/kvm` accessible)
- Docker + Docker Compose v2
- ~80 GB free disk for the default 64 GB virtual disk

## Quickstart

```bash
cp .env.example .env
# Edit .env — at minimum set WIN_PASSWORD
make up
```

First boot takes 15–30 minutes (Windows install + Office download + PHP setup). Watch progress at <http://localhost:8006>.

`make up` blocks until every phase completes. The container status shows `healthy` when done.

## Access

- Web viewer: <http://localhost:8006>
- RDP: `localhost:3389` with the credentials from `.env`

## Re-deploy

To apply a config change without reinstalling Windows:

```bash
# Edit one or more of these:
#   shared/.runtime/php-config.ini       <- triggers phase-php
#   shared/.runtime/post-install.bat     <- triggers phase-code

make redeploy
```

`make redeploy` deletes the healthcheck signal, restarts the Windows container (a ~60s VM cold boot), and waits for the dispatcher to write `shared/install.done` again. The dispatcher hashes the runtime files, skips any phase whose hash is unchanged, and runs only the affected phase.

Typical redeploy times:

| Change | Time |
|---|---|
| Just `post-install.bat` (project code) | ~60s boot + your composer install |
| `php-config.ini` (version, extensions) | ~60s boot + ~30s PHP download/extract + composer install |
| Both | Sum of the above |
| First install ever | 15–30 min |

## Customization

### PHP version and extensions

Edit `shared/.runtime/php-config.ini`:

```ini
version = 8.4.8           ; must match a release on windows.php.net
extension = curl          ; one extension per line
memory_limit = 512M       ; any php.ini directive
```

The VS toolset (`vs16` / `vs17`) is auto-derived from the PHP minor version. `openssl` and `curl` are always enabled regardless of what's in this file.

Redeploy with `make redeploy`. The dispatcher detects the changed hash, atomically swaps `C:\php` to the new build, and rolls back automatically if the smoke test fails.

### Post-install commands

Edit `shared/.runtime/post-install.bat`. PHP, Composer, and Git are on PATH. Runs at the end of phase-code, every time phase-code re-runs.

The script should be **idempotent**: prefer `git -C dir pull` over `git clone`; rely on `composer install` being idempotent. If you start long-running processes (queue workers, etc.), pair this with `post-install-stop.bat` (see below).

### Stopping services before a PHP swap

When `phase-php` re-runs, it has to rename `C:\php` out of the way. If anything has open handles on `C:\php\*` — a Laravel queue worker, php-cgi, a service — the rename fails. Copy `shared/.runtime/post-install-stop.bat.example` to `post-install-stop.bat` and add the relevant `taskkill` / `sc stop` commands. The dispatcher calls it automatically before phase-php starts touching `C:\php`.

### Office product / language

Edit `oem/office-config.xml`. This is part of phase-base, so changes require `make reset` to take effect.

### Project files

Anything in `./shared/` (outside `shared/.runtime/`) is exposed inside Windows over SMB at `\\host.lan\Data` and mirrored to `C:\Projects` during phase-code. Note that phase-code only re-runs when `post-install.bat`'s hash changes — if you change project files in `shared/` without changing the post-install hook, `make redeploy` won't pick them up. Edit `post-install.bat` (or add a comment line) to force a phase-code re-run.

### Git credentials (optional)

For private repo clones in `post-install.bat`:

```bash
cp oem/git-credentials.txt.example oem/git-credentials.txt
# Edit with your PAT
```

Phase-base copies it to `%USERPROFILE%\.git-credentials` and enables the `store` credential helper. Once baked in, it survives redeploys.

## Files and layout

```
Makefile                          # up / redeploy / reset / logs targets
docker-compose.yml                # compose definition
.env / .env.example               # all tunables
oem/                              # OOBE-time only (mounted ro at /oem)
  install.bat                     # first-boot entry, runs phase-base
  boot-launcher.bat               # baked into C:\OEM-bootstrap on first boot
  office-config.xml               # ODT configuration (phase-base)
  scripts/
    get-odt.ps1                   # phase-base: Office Deployment Tool
    get-git.ps1                   # phase-base: Git release fetcher
    retry-download.ps1            # phase-base: bounded retry helper
    register-task.ps1             # phase-base: registers OEM-Dispatcher task
  git-credentials.txt             # optional, gitignored
shared/                           # exposed at \\host.lan\Data inside the VM
  .runtime/                       # orchestrator + user config (committed)
    dispatcher.bat                # phase orchestrator (boot-launcher invokes)
    phase-php.bat                 # PHP install w/ atomic swap + rollback
    phase-code.bat                # project mirror + post-install
    php-config.ini                # user-edits this
    post-install.bat              # user-edits this
    post-install-stop.bat.example # rename to enable
    scripts/                      # PowerShell helpers used by phase-*
  <your project files>            # mirrored to C:\Projects every phase-code
storage/                          # VM disk + state (created on first boot)
k8s/                              # Kubernetes manifest example
```

## Make targets

| Command | What it does |
|---|---|
| `make up` | Start (or resume) and wait until every phase completes |
| `make redeploy` | Reboot Windows so the dispatcher fires; only changed phases re-run |
| `make reset` | Tear down, wipe the VM disk, and start fresh — no sudo needed |
| `make logs` | Tail the container (dockur) logs |
| `make logs-dispatcher` | Tail the dispatcher log written by the VM to `shared/.logs/dispatcher.log` |

## Logs and state on the VM

After first boot, these paths exist on the Windows VM:

| Path | Purpose |
|---|---|
| `C:\OEM-state\phase-base.done` | Phase-base completion marker |
| `C:\OEM-state\phase-php.done` + `.hash` | Phase-php marker + hash of last `php-config.ini` |
| `C:\OEM-state\phase-code.done` + `.hash` | Phase-code marker + hash of last `post-install.bat` |
| `C:\OEM-state\phase-*.running` | Present only while a phase is mid-run; left behind on crash to force re-run |
| `C:\OEM-logs\install.log` | First-boot phase-base log |
| `C:\OEM-logs\dispatcher.log` | Per-boot dispatcher log (local fallback if SMB unwritable) |
| `\\host.lan\Data\.logs\dispatcher.log` | Per-boot dispatcher log on the SMB share — visible from the host at `shared/.logs/dispatcher.log` |
| `C:\OEM-logs\boot-launcher.log` | Per-boot launcher log (local only — SMB may not be up yet) |
| `C:\OEM-bootstrap\boot-launcher.bat` | The scheduled task target (baked once) |
| `C:\OEM-runtime\` | Fresh copy of `\\host.lan\Data\.runtime\` written each boot |

To force a phase to re-run without changing its trigger input, RDP in and delete the corresponding `.done` and `.hash` files, then `make redeploy`.

## Kubernetes

The phased layout was designed with k8s in mind. The split mirrors how Kubernetes wants you to think about state:

- **PVC for `/storage`** — holds the activated Windows VM disk and all phase markers. Survives every pod restart, every Helm rollout. Lose it and you re-run phase-base.
- **PVC for `/shared`** — small writable volume the VM uses for project files and the `install.done` healthcheck signal. (Pure ConfigMap mounts don't work here — the VM writes to it.)
- **ConfigMap for `/runtime-config`** — the orchestrator (`dispatcher.bat`, `phase-php.bat`, `phase-code.bat`) plus your user-editable config (`php-config.ini`, `post-install.bat`). An init container copies it into `/shared/.runtime/` on every pod start.
- **ConfigMap for `/oem`** — the one-shot bootstrap files dockur consumes during OOBE.
- **Secret for `WIN_PASSWORD`** (and `git-credentials.txt` if used).

### Redeploy flow in k8s

1. Edit `php-config.ini` in your Helm values (or `kubectl edit configmap windows-runtime`).
2. Apply. The `checksum/runtime` annotation on the StatefulSet pod template changes.
3. Kubernetes rolls the pod. The init container repopulates `/shared/.runtime/`.
4. Windows boots in ~60s from the same PVC. The scheduled task fires.
5. Dispatcher hashes `php-config.ini`, sees it differs from the stored hash, and re-runs phase-php only.
6. Readiness probe flips back to ready when `install.done` reappears.

### Golden image pattern

The cleanest scaling pattern for windows-on-k8s: once a fresh install completes phase-base, snapshot the `/storage` PVC. New tenants provision from the snapshot — phase-base is already done, so they only run phase-php + phase-code on first boot (~2 min instead of ~30).

A minimal example manifest lives in [`k8s/`](k8s/). See `k8s/README.md` for the full pattern.

### k8s-specific gotchas

- **KVM access** — managed k8s services don't usually expose `/dev/kvm` on shared nodes. Use bare-metal nodes, KubeVirt's device plugin, or node pools with nested virtualization enabled.
- **PVC binding mode** — use `WaitForFirstConsumer` so the disk lands on a node that has KVM.
- **ConfigMap propagation** — kubelet syncs mounted ConfigMaps every ~60s, but the pod rollout triggered by the checksum annotation bypasses that. If you edit a ConfigMap without rolling the pod, the VM won't see the change until next boot anyway.
- **Activation per disk** — TSforge writes to the activated Windows install. Cloning a fully-activated PVC carries activation with it; a brand-new disk re-runs phase-base.

## Gotchas

- **Phase-code skips unchanged project files.** Phase-code only re-runs when `post-install.bat`'s hash changes. If you only change files under `shared/`, edit `post-install.bat` (a comment line is enough) to bump its hash.
- **post-install must be idempotent.** It runs on first install AND on every config-triggered redeploy. Prefer `git pull` over `git clone`; ensure migrations are safe to re-run.
- **Long-running workers + PHP swap.** Without a `post-install-stop.bat`, a PHP version bump may fail to rename `C:\php` because a queue worker is holding the DLLs open. Provide a stop hook for anything that pins `C:\php`.
- **dockur shared path** — dockur exposes `./shared` at `\\host.lan\Data`, *not* `C:\Shared`. The dispatcher reads from the UNC path.
- **Activation** — `10` (Windows 10 Pro) is a non-eval edition. Avoid `10l` (LTSC eval) — TSforge can't permanently activate it. `Ohook` activates Office permanently.
- **Resource hogging** — `RAM_SIZE` and `DISK_SIZE` reserve at compose-up. Adjust before first boot — resizing afterwards is non-trivial.
- **Stop gracefully** — `stop_grace_period: 2m` lets Windows shut down cleanly. Don't `kill -9`.
