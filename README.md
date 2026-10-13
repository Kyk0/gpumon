<p align="center"><img src="docs/icon.png" width="96" alt=""></p>

<h1 align="center">GPU Monitor</h1>

<p align="center">
A macOS desktop widget that shows every GPU on your SSH servers:<br>
load, VRAM, and who's using it, at a glance.
</p>

<p align="center">
<a href="https://github.com/Kyk0/gpumon/actions/workflows/build.yml"><img src="https://github.com/Kyk0/gpumon/actions/workflows/build.yml/badge.svg" alt="build"></a>
<img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
<img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
</p>

<p align="center"><img src="docs/screenshot.png" width="330" alt="GPU Monitor widget"></p>

Shared lab servers, one H100, five people. Stop running `ssh … nvidia-smi` in three terminals to find a free GPU.
GPU Monitor sits on your desktop and keeps all of it in view. Nothing is installed on the servers: it runs `nvidia-smi` over the SSH keys you already have.

## Features

- **Cluster at a glance**: average load, free VRAM, idle GPUs, and how many jobs are yours.
- **A card per GPU**: a load ring, a 15-minute load/VRAM graph, temperature, power, and the server's CPU and RAM.
- **Who's using it**: the VRAM bar is split by user, with each user's memory and runtime. Your jobs are in blue. Click a card to see every process and its command.
- **Best now**: the GPU with the most free VRAM. Click it to copy `ssh … CUDA_VISIBLE_DEVICES=N`.
- **Settings in the widget**: add or remove servers, pin it to the desktop / a normal window / always on top, and pick its height.
- **Web dashboard** with history at <http://localhost:8765>, if you prefer a browser tab.

## Install

You need:
- macOS 14+
- Xcode command line tools (`xcode-select --install`)
- Python 3 (standard library only)
- passwordless SSH to each server (`ssh user@host` works without a prompt)

```bash
git clone https://github.com/Kyk0/gpumon.git
cd gpumon
./install.sh
```

**GPU Monitor** lands in `/Applications` and starts at login. Click **Settings** in the widget to add servers by name and ssh target (`user@host` or an alias from `~/.ssh/config`).

To update, run `git pull && ./install.sh`. To remove, run `./uninstall.sh`. Your server list is kept in `~/.config/gpumon/hosts.json`.

## How it works

```
┌──────────────── your Mac ────────────────┐           ┌──── servers ────┐
│ GPU Monitor.app ──► backend/gpumon.py ───┼── ssh ───►│ nvidia-smi, ps  │
│ (SwiftUI widget)    127.0.0.1:8765        │  every 5s │                 │
└──────────────────────────────────────────┘           └─────────────────┘
```

- `backend/gpumon.py` is stdlib-only Python. It keeps one multiplexed SSH connection per server (`ControlMaster`), runs `nvidia-smi` and `ps` to map processes to users, and serves JSON plus the web dashboard on localhost.
- `app/Sources/` holds the SwiftUI widget. It's built with plain `swiftc`, no Xcode project needed.
- `install.sh` builds the app, renders its icon, and registers two launch agents. Logs go to `/tmp/local.gpumon.*.log`.

```
app/Sources/      SwiftUI widget (main, Model, Panel, Cards, Settings, Theme, Icon)
backend/          gpumon.py + dashboard.html
docs/             screenshot, icon, demo data used for the screenshot
install.sh        build + install + autostart
uninstall.sh
```

## License

MIT
