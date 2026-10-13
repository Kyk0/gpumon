# gpumon

See every GPU on your SSH servers at a glance: utilization, VRAM, and who is running what.
macOS menu bar app + desktop widget + web dashboard. No agents on the servers: it just runs
`nvidia-smi` over your existing SSH keys every 5 seconds.

- **Menu bar**: one column per server, `A 99%` (GPU util) over `14/94G` (VRAM used/total), color-coded.
  Click for per-GPU details and the process list.
- **Desktop panel**: sits on the desktop like a widget (or as a normal / always-on-top window).
  GPU + VRAM bars and every process: user, VRAM, runtime, command. Your own processes are highlighted.
- **Dashboard** at <http://localhost:8765>: cards with 15-minute history, CPU load/RAM,
  and a "best place to launch now" pick (the GPU with the most free VRAM).
- **Add / remove servers** from the dashboard (⚙ Servers). No config files to edit.

## Install

Requirements: macOS 13+, Xcode command line tools (`xcode-select --install`), Python 3 (stdlib only),
and passwordless SSH (`ssh user@host` works without a prompt) to each server.

```bash
git clone https://github.com/Kyk0/gpumon.git ~/gpumon
cd ~/gpumon
./install.sh
```

This builds `~/Applications/GPUBar.app` and registers two login agents, so everything starts
automatically at login. Then open <http://localhost:8765/#servers> (or menu bar → *Add / Remove Servers…*)
and add your servers:

| name  | ssh target                         |
|-------|------------------------------------|
| box1  | `me@gpu-box-1.example.edu`         |
| lab   | `my-ssh-config-alias`              |

Servers are saved to `hosts.json` (git-ignored; see `hosts.example.json`).

## Usage

- Menu bar → **Panel Position**: *On Desktop (widget)*, *Normal Window*, or *Always on Top*. Drag the panel anywhere; its position is remembered.
- Menu bar → **Show/Hide Panel** (⌘P), **Open Dashboard** (⌘D).
- "Best now" in the menu copies an `ssh … CUDA_VISIBLE_DEVICES=N` command to the clipboard.

After editing `gpumon.py` or `GPUBar.swift`, run `./install.sh` again. Logs: `/tmp/local.gpumon.*.log`.

## Uninstall

```bash
./uninstall.sh
```

## How it works

`gpumon.py` keeps one multiplexed SSH connection per server (`ControlMaster`) and every 5 s runs
`nvidia-smi --query-gpu`, `nvidia-smi --query-compute-apps` and `ps` to map PIDs to users. It serves
`/api/status` (JSON) and the dashboard on `127.0.0.1:8765`. `GPUBar.app` reads that JSON.
