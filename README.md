# Omarchy News

Every Omarchy announcement, read from the bar the moment it drops.

Omarchy News watches the official `omarchy.org/news` feed. It adds an unread dot to the bar, a keyboard-first post list, and a typeset reader inside the panel.

## Features

- Tracks the official Omarchy News RSS feed.
- Separates unseen posts from posts you have not read.
- Reads full posts and their images without leaving the panel.
- Uses Omarchy's current dark or light theme.
- Sends one desktop notification when a fetch finds new posts.

## Install

Installation instructions will be verified on Omarchy before the first release.

## Keybinding

Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + N", "Omarchy News", "omarchy-shell shell toggle io.github.eliasstravik.omarchy-news")
```

## Controls

The complete mouse and keyboard table will be added after live input testing.

## Settings

The plugin will expose refresh interval, notification, and retained-post settings through the bar configuration.

## IPC

The panel will support open, close, show, hide, toggle, refresh, mark-all-read, and status commands.

## How it works

The service fetches `https://omarchy.org/news/rss.xml` on a timer. First-run, seen, read, and notification behavior will be documented after the service passes live testing.

## What it executes exactly

Runtime commands and their fixed argument lists will be documented when the service is implemented.

## Data and privacy

The plugin contacts only hosts named by the official Omarchy feed. Cache and state paths, limits, and retention will be documented before release.

## Remove

Removal instructions will be verified before release.

## Light theme

A light-theme screenshot will be added after testing on Omarchy.

## Local development

Run the portable checks with:

```bash
node --test tests/*.test.mjs
bash tests/qml-source-test.sh
```

QML linting and `omarchy plugin validate .` run on an Omarchy machine.

## License

[MIT](LICENSE)
