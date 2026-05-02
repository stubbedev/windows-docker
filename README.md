# windows-docker

Spins up Windows 10 Pro in a container using [dockur/windows](https://github.com/dockur/windows), then runs an unattended OEM script that:

1. Permanently activates Windows (TSforge via [MAS](https://massgrave.dev/))
2. Installs and permanently activates Microsoft Office 2024 LTSC (Ohook)
3. Installs Git for Windows
4. Installs PHP (configurable version) + Composer
5. Optionally configures Git credentials
6. Copies your project files in and runs your post-install hooks

The whole stack is configured for running PHP-based post-install jobs (Composer install, Laravel queues, etc.) inside Windows.

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

`make up` blocks until the full setup — including your `post-install.bat` — is complete. The container status shows `healthy` when done. The full log is at `C:\OEM-logs\install.log` inside the VM.

## Access

- Web viewer: <http://localhost:8006>
- RDP: `localhost:3389` with the credentials from `.env`

## Customization

### PHP version and extensions

Edit `oem/php-config.ini`:

```ini
version = 8.4.8           ; must match a release on windows.php.net
extension = curl          ; one extension per line
memory_limit = 512M       ; any php.ini directive
```

The toolset (`vs16`/`vs17`) is auto-derived from the PHP minor version. `openssl` and `curl` are always enabled regardless of what's in this file.

### Office product / language

Edit `oem/office-config.xml`. The default installs Office Pro Plus 2024 Volume in en-us with Groove/Bing/Lync excluded.

### Post-install commands

Edit `oem/post-install.bat`. Runs after Git/PHP/Composer are on PATH. Examples are in the file (clone, `composer install`, start a queue worker).

### Project files

Anything in `./shared/` is exposed inside Windows over SMB at `\\host.lan\Data` and copied to `C:\Projects` during install.

### Git credentials (optional)

For private repo clones in `post-install.bat`:

```bash
cp oem/git-credentials.txt.example oem/git-credentials.txt
# Edit with your PAT
```

`install.bat` copies it to `%USERPROFILE%\.git-credentials` and enables the `store` credential helper. The source file is deleted from `C:\OEM` during cleanup. The file is gitignored.

## Files and layout

```
Makefile                    # up / reset / logs targets
docker-compose.yml          # compose definition (reads .env)
.env / .env.example         # all tunables
oem/
  install.bat               # main OEM bootstrap (runs once on first boot)
  post-install.bat          # your custom commands
  office-config.xml         # ODT configuration
  php-config.ini            # PHP version + ini directives + extensions
  git-credentials.txt       # optional, gitignored
  scripts/                  # PowerShell helpers called by install.bat
shared/                     # files exposed to Windows at \\host.lan\Data
storage/                    # VM disk + state (created on first boot)
```

## Make targets

| Command | What it does |
|---|---|
| `make up` | Start (or resume) and wait until setup is fully complete |
| `make reset` | Tear down, wipe the VM disk, and start fresh — no sudo needed |
| `make logs` | Tail the container logs |

## Gotchas

- **Once-only OEM**: `install.bat` writes `C:\OEM-logs\install.done` when it finishes. To re-run it, use `make reset` which wipes the VM disk entirely.
- **dockur shared path**: dockur exposes `./shared` at `\\host.lan\Data`, *not* `C:\Shared`. The script copies from the UNC path.
- **Activation**: `10` (Windows 10 Pro) is a non-eval edition — TSforge permanently activates it via ticket spoofing. Ohook permanently activates Office. Both survive reboots and updates. Avoid `10l` (LTSC) — it downloads an evaluation ISO that cannot be permanently activated.
- **Resource hogging**: `RAM_SIZE` and `DISK_SIZE` reserve at compose-up. Adjust before first boot — resizing afterwards is non-trivial.
- **Stop gracefully**: `stop_grace_period: 2m` lets Windows shut down cleanly. Don't `kill -9`.
