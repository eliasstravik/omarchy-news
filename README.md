# Omarchy News

A dedicated Omarchy panel for the Omacom Foundation's news feed.

## Goal

Omarchy now publishes its `/news` as RSS at <https://omarchy.org/news/rss.xml>.
DHH asked whether someone would build a dedicated Omarchy panel for it:

> It's hard to keep up with all the insane announcements we're dropping for the
> Omacom Foundation. And there are many, many more to come. You can now
> subscribe to the /news via RSS. Maybe someone will make a dedicated panel for
> Omarchy for it?
>
> — https://x.com/dhh/status/2095473790650048879

This repository is that panel.

## Feed

- URL: `https://omarchy.org/news/rss.xml`
- Format: RSS 2.0 with `content:encoded` full bodies and `dc:creator` authors
- Items link to `https://omarchy.org/news/<year>/<month>/<slug>`

## Status

Scaffolded and tracked in the Omarchy News GitHub Project. Work is planned
through issues in this repository.
