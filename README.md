# SABnzbd Monitor

A DankMaterialShell plugin that monitors your [SABnzbd](https://sabnzbd.org/) download queue and displays the current status in your status bar.

## Features

- Shows current queue status: **Downloading**, **Paused**, or **Idle**
- Displays live download speed when active
- Popout panel with remaining size, time left, and queue item count
- Current job name and progress in the popout
- Queue controls in popout: **Pause**, **Resume**, and **Refresh**
- Configurable refresh interval with exponential backoff when unreachable
- Optional compact pill modes: `full`, `text`, or `icon`

## Setup

1. Open plugin settings.
2. Set the **SABnzbd URL** (default: `http://localhost:8080`).
3. Enter your **API Key** — find it in SABnzbd under **Config → General → API Key**.
4. Optional settings:
	- **Refresh Interval (seconds)**: 2-60
	- **Pill Mode**: `full`, `text`, or `icon`

## Requirements

- SABnzbd must be reachable from the host running DankMaterialShell.

## Screenshots

### Dankbar States

Idle

![Dankbar idle state](screenshots/dankbar_idle.png)

Paused

![Dankbar paused state](screenshots/dankbar_paused.png)

Downloading with speed

![Dankbar downloading speed state](screenshots/dankbar_speed.png)

### Popout Panel

Idle popout

![Popout idle state](screenshots/popout_idle.png)

Downloading popout

![Popout downloading state](screenshots/popout_downloading.png)
