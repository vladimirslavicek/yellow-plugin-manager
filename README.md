# Yellow Plugin Manager

A native macOS app that lists every audio plugin on your Mac, compares the installed formats side by side and moves plugins you are not using out of the way, so your DAWs scan and show less.

- Formats: VST2, VST3, AU, AAX, CLAP
- Requires macOS 14 Sonoma or later, Apple Silicon or Intel

## What it does

- **One table for everything.** Plugins grouped by vendor, with a column per format showing whether it is used, parked in Unused, or not installed. Version, install date and architecture alongside.
- **Used / Unused.** "Unused" plugins are moved to a sibling folder such as `VST3 (Unused)` or Avid's `Plug-Ins (Unused)`, keeping their subfolders, and can be moved back at any time.
- **Staged changes.** Nothing moves until you press Apply Changes. Staged rows are highlighted and a banner shows what will happen.
- **Groups.** Named sets of plugins with a switch. Membership comes from rules (name starts with, name contains, vendor is) or from plugins you add by hand. A plugin belongs to at most one group. A warning appears when a group's plugins no longer match its switch, for example after an installer put them back.
- **Single formats.** Park only the AAX version of a plugin and keep its VST3.
- **Markdown export** of the selection or current view, ready to hand to an LLM to check for outdated versions.

## Install

1. Download the latest zip from [Releases](../../releases) and unzip it.
2. Move **Yellow Plugin Manager.app** to Applications.
3. The app is not notarized by Apple, so macOS blocks the first launch. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. Alternatively, in Terminal:

   ```
   xattr -dr com.apple.quarantine "/Applications/Yellow Plugin Manager.app"
   ```

## Before you use it

This app moves plugin bundles inside `/Library`. Please read this first.

- Moves that need it ask for an administrator password, once per batch.
- If a plugin already exists at the destination, the copy that was there is sent to the Trash, not deleted.
- There is no undo history yet. To revert, mark the plugins Used again and apply.
- DAWs keep plugin caches. After moving plugins, a DAW may need a rescan.
- Tested on a single machine so far. Keep a backup of your plugin folders the first time you try it.

## Folders

- **VST2**: used `/Library/Audio/Plug-Ins/VST`, unused `/Library/Audio/Plug-Ins/VST (Unused)`
- **VST3**: used `/Library/Audio/Plug-Ins/VST3`, unused `/Library/Audio/Plug-Ins/VST3 (Unused)`
- **AU**: used `/Library/Audio/Plug-Ins/Components`, unused `/Library/Audio/Plug-Ins/Components (Unused)`
- **CLAP**: used `/Library/Audio/Plug-Ins/CLAP`, unused `/Library/Audio/Plug-Ins/CLAP (Unused)`
- **AAX**: used `/Library/Application Support/Avid/Audio/Plug-Ins`, unused `/Library/Application Support/Avid/Audio/Plug-Ins (Unused)`

The same pairs are scanned under `~/Library` (except AAX). Groups are stored in `~/Library/Application Support/YellowPluginManager/groups.json`.

## Build from source

Only the Xcode Command Line Tools are needed, not Xcode.

```
sh build-app.sh
```

This produces a universal `build/Yellow Plugin Manager.app` and a zip in `dist/`. The app icon is drawn by `scripts/make-icon.swift` during the build.

`--selftest` on the binary prints a read-only summary of what was found, without opening a window.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
