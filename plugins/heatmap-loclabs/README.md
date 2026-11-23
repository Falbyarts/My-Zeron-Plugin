# Heatmap-LocLabs

A year of **local** commits under a new chat's composer, one square a day,
shaded by how many commits it holds in the accent you chose. Rest the pointer
on a day to open a floating card above that cell listing up to 10 of that
day's newest commits, each with its time and message. Move the pointer into
the card to keep it open and click `+N more` to expand and scroll all saved
commits locally (read-only, no external links).

- Reads the git folders this device's chats and projects point at
  (`git log --all`; every commit counts, whichever of your emails authored it).
- Configure visibility and scope in **Settings → Plugins → Heatmap-LocLabs**:
  - **Show heatmap** — show or hide the heatmap under a new chat's composer.
  - **Commit scope** — count commits from **All folders** on this device, or
    only the **Selected project** in the composer (falls back to all local
    folders when **No project** is selected; reads from the project's device
    when Heatmap-LocLabs is installed and allowed there).
- Nothing comes from GitHub: all commit history is read directly from local
  repositories.
- Kept for 5 minutes; the refresh button beside the count re-reads immediately
  and updates the count, grid, and day cards in place.

Files: `init.luau` (the heatmap and its cards), `service.luau` (the git work),
`locales/en.json` (its words).
