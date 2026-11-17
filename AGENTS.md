# AGENTS.md — zeron-plugins

This repository is the source of truth for Falbyarts' Zeron plugins, published at
`github.com/Falbyarts/zeron-plugins`. Humans install signed `.zeron-plugin` files
from Releases; the repo keeps the signed plugin folders and the docs.

## Where things are

- Repo root: this folder (`zgx_plugin`).
- Live plugins (what Zeron loads, signs and reloads): `%LOCALAPPDATA%\Zeron\plugins\<id>`.
- Repo copies: `plugins/<id>/` — must stay byte-identical to the live folder.
- Docs: `docs/<id>.md`; preview images: `assets/`.

## Golden rules

1. **Never edit `signature` in `zeron-plugin.json` by hand.** Zeron re-signs the
   plugin when its files are saved, and `export_plugin` signs again before
   packaging. A hand-edited signature breaks installation.
2. **Edit the live plugin, then copy live → repo.** Never edit the repo copy and
   expect Zeron to load it; the repo is a mirror, not the runtime.
3. **Verify hashes after every sync** (see below). `plugins/<id>/` must match the
   live folder exactly, or the release asset and repo install will disagree.
4. **Bump `version` in `zeron-plugin.json`** for every user-visible change.
5. **Tag and asset names:** tag `<id>-v<version>`, asset
   `<id>-<version>.zeron-plugin`.
6. **Update the README table and `docs/<id>.md`** whenever a plugin is added,
   renamed, or its behaviour changes.
7. **Never commit tokens, passwords, `.env`, or credential files.** Git auth goes
   through Git Credential Manager (GCM); do not print the token.
8. **A plugin's permissions are part of its contract.** Adding one requires a new
   version and the person allows it again in Zeron.

## Workflows

### Create a plugin

1. `create_plugin { id, name, description, permissions }`.
2. Write `init.luau`, `icon.svg`, `locales/en.json`, `README.md` and the manifest
   in the live folder.
3. `plugin_status { id }` until it is **on** with no problem. Use
   `describe_elements` when a selector matches 0.
4. `export_plugin { id }` when it is ready to ship.
5. Copy the live folder to `plugins/<id>/`, then verify hashes.
6. Add the README row, `docs/<id>.md`, and a preview image if useful.
7. Commit, push, and create the GitHub release.

### Change a plugin

1. Edit the live folder.
2. `plugin_status { id }` until clean.
3. Bump `version` in the manifest.
4. `export_plugin { id }`.
5. Sync live → repo, verify hashes, commit, push, release.

### Sync live → repo (PowerShell)

```powershell
$id = 'heatmap-loclabs'
$live = Join-Path $env:LOCALAPPDATA "Zeron\plugins\$id"
$repo = Join-Path (Get-Location) "plugins\$id"
Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item $live $repo -Recurse
```

### Verify the signature

```powershell
$dir = Join-Path (Get-Location) 'plugins\heatmap-loclabs'
$m = Get-Content (Join-Path $dir 'zeron-plugin.json') -Raw | ConvertFrom-Json
$bad = 0
foreach ($p in $m.signature.files.PSObject.Properties.Name) {
	$h = (Get-FileHash (Join-Path $dir $p) -Algorithm SHA256).Hash.ToLower()
	if ($h -ne $m.signature.files.$p) { Write-Output "MISMATCH $p"; $bad++ }
}
Write-Output "signature_mismatches=$bad"
```

`signature_mismatches=0` before committing.

### Release

Use the GitHub REST API with the token GCM already stores, or `gh release create`
when it is installed. Never echo the token.

- Tag: `<id>-v<version>`.
- Asset: the `export_plugin` file, named `<id>-<version>.zeron-plugin`.
- Release notes: what changed and the install steps, in Indonesian.

## Commit style

`feat(<id>): ...`, `fix(<id>): ...`, `docs: ...`, `chore: ...`.

## Definition of done

- `plugin_status` says **on**, no problem.
- `plugins/<id>/` hash-verified against the live folder.
- Version bumped; release exists with a matching asset.
- README and docs updated.
- Working tree clean and pushed to `main`.
