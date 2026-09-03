# Omarchy News

Every Omarchy announcement, read from the bar the moment it drops. A dot on the
bar icon when [omarchy.org/news](https://omarchy.org/news) has something you
have not seen, a keyboard-first list, and a reader that keeps the full article
and its images inside the panel.

![Opening Omarchy News from the bar, moving through the list, and reading two posts](docs/news-tour.gif)

## Install

```bash
omarchy plugin add https://github.com/eliasstravik/omarchy-news --enable
~/.config/omarchy/plugins/io.github.eliasstravik.omarchy-news/bin/omarchy-news-setup
```

The first line is the whole install. The second is optional: it offers the
`Super+Alt+N` keybinding, and nothing is written to `~/.config/hypr/bindings.lua`
without your yes (a timestamped backup is taken first). `--yes` accepts it for
unattended runs, `--skip-keybinding` leaves the file alone.

To bind by hand instead, add this to `bindings.lua`:

```lua
o.bind("SUPER + ALT + N", "Omarchy News", "omarchy-shell shell toggle io.github.eliasstravik.omarchy-news")
```

## Use

Click the bar icon or press `Super+Alt+N`. Then `j`/`k` to move, `Enter` to read,
`o` to open in the browser, `A` to mark everything read (with a five-second undo),
`?` for every other key, `Esc` to close.

| Setting | Default | Change it |
|---|---|---|
| Refresh interval | 30 min | `omarchy bar set io.github.eliasstravik.omarchy-news refreshMinutes 15` |
| Notify on new posts | on | `omarchy bar set io.github.eliasstravik.omarchy-news notify false` |
| Posts to keep | 40 | `omarchy bar set io.github.eliasstravik.omarchy-news maxPosts 60` |

## Remove

```bash
omarchy plugin remove io.github.eliasstravik.omarchy-news --yes
rm -rf ~/.cache/omarchy-news ~/.local/state/omarchy-news
```

If you accepted the keybinding, delete the `Omarchy News` line from
`~/.config/hypr/bindings.lua` or restore the backup next to it.

## What it touches

One shared service fetches `https://omarchy.org/news/rss.xml` with `curl` over
HTTPS only, caches article images from that feed, and notifies through
`omarchy-notification-send`. Every command is a fixed argument list: no shell
strings, sockets, daemons, or elevated privileges. The feed cache lives in
`~/.cache/omarchy-news`, read state in `~/.local/state/omarchy-news`. Nothing
else on the machine is read or written.

## License

[MIT](LICENSE)
