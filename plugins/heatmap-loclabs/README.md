# Heatmap-LocLabs

A year of **local** commits under a new chat's composer, one square a day,
shaded by how many commits it holds in the accent you chose. Rest the pointer
on a day and a card lists up to 10 of that day's newest commits (with `+N more`
when a day holds more), each with its time and message.

- Reads the git folders this device's chats and projects point at, on this
  device only (`git log --all`; every commit counts, whichever of your emails
  authored it).
- Nothing comes from GitHub or another machine: a commit made on another
  computer shows on that computer's heatmap, not here.
- Kept for 5 minutes; the refresh button beside the count re-reads your folders
  immediately and updates the count, grid, and day cards in place.

Files: `init.luau` (the heatmap and its cards), `service.luau` (the git work),
`locales/en.json` (its words).
