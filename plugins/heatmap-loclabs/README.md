# Heatmap-LocLabs

A year of **local** commits under a new chat's composer, one square a day,
shaded by how many commits it holds in the theme's accent. Rest the pointer
on a day and a card lists that day's commits, newest first, with each
commit's time and message.

- Reads the git folders this device's chats and projects point at, on this
  device only (`git log --all`; every commit counts, whichever of your emails
  authored it).
- Nothing comes from GitHub or another machine: a commit made on another
  computer shows on that computer's heatmap, not here.
- Kept for 5 minutes; opening a new chat again reads it once more.

Files: `init.luau` (the heatmap and its cards), `service.luau` (the git work),
`locales/en.json` (its words).
