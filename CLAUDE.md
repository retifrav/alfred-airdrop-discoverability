# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An [Alfred](https://alfredapp.com) workflow that sets AirDrop discoverability (No One / Contacts Only / Everyone) by clicking through the macOS UI via Accessibility from AppleScript, since macOS offers no API for it. There is no build system, linter or test suite. All logic is one AppleScript embedded as a string in `src/info.plist`; `src/` as a whole is the workflow folder (`info.plist`, `icon.png`, `List Filter Images/`).

Nothing here can run in the container: there is no `osascript`, `osacompile`, `plutil` or Alfred on Linux, and the script's behaviour depends on the live macOS UI. A behavioural change is unverified until the user runs it on a Mac, so say that rather than claiming it works.

## Commands

```sh
# the only check available in the container: the plist still parses
python3 -c 'import plistlib; plistlib.load(open("src/info.plist", "rb"))'

# print the embedded AppleScript unescaped, for reading or diffing
python3 -c 'import plistlib; print(next(o["config"]["script"] for o in plistlib.load(open("src/info.plist", "rb"))["objects"] if o["type"] == "alfred.workflow.action.script"))'
```

Host-side only (macOS): `plutil -lint src/info.plist`, and `osacompile -o <tmp>.scpt <file>` on the extracted script checks its syntax without clicking anything.

## Architecture

`src/info.plist` is an Alfred object graph wired by UID in `connections` (`uidata` holds only editor-canvas positions):

1. keyword `airdrop` (`alfred.workflow.input.keyword`) →
2. list filter (`alfred.workflow.input.listfilter`) whose `items` is a JSON string mapping No One / Contacts Only / Everyone to arg `1` / `2` / `3`, each with an icon referenced by file name from `src/List Filter Images/` →
3. script action (`alfred.workflow.action.script`, `type` 6 = AppleScript, `scriptargtype` 1 = argv) receiving that arg.

The level number doubles as the UI ordinal: `checkbox <level>` in the Control Centre AirDrop module and `button <level>` in Finder's "Allow me to be discovered by" pop-over. The 1/2/3 mapping therefore follows macOS's own control order and can't be renumbered on its own.

Script flow: `run` → `applyDiscoverabilityLevel` (validates 1–3) → `toggleAirDropViaMenuBar`, which clicks the AirDrop Menu Bar item in the `ControlCenter` process. If anything in that `try` fails (e.g. no AirDrop icon on the Menu Bar) it ends up in `toggleAirDropViaFinder` (new Finder window, ⇧⌘R, dropdown, pop-over button). The Control Centre route between the two deliberately just throws, because Control Centre's AirDrop options are not reachable through Accessibility. Afterwards, for level 1 with the user-configuration checkbox `TOGGLE_OFF_BLUETOOTH` set (declared in `userconfigurationconfig`, read via `system attribute`), `toggleBluetoothOff` tries the Bluetooth Menu Bar item, then Control Centre `checkbox 3`, and errors if neither is there.

## Editing rules

- Edit `src/info.plist` as text. The script is XML-escaped inside its `<string>`, so `>` / `<` / `&` are written `&gt;` / `&lt;` / `&amp;` (see `argc &gt; 1`, `" &amp; ex`). Don't write the file back through `plistlib.dump`: it reformats the `uidata` reals (`<real>145</real>` → `145.0`), a spurious diff. Re-run the parse check after every edit.
- The plist structure is indented with tabs (Alfred's output); the AppleScript body uses 4 spaces.
- UI paths are ordinals (`group 1 of splitter group 1 of window 1`) because the controls have no IDs or labels, so they break with macOS updates, which is the usual reason to touch this code. Elements found by name use the literal strings `"AirDrop"`, `"Bluetooth"` and `"Control Centre"`; keep the British spelling.
- In `toggleAirDropViaFinder`, testing `button 2` first and falling back to `button 1` is deliberate: since Sequoia 15.5, testing `button 1` first reports it as existing even when `2` is the real one. Don't invert it.
- Keep the commented-out blocks and long comments in the script; they record approaches that stopped working on specific macOS versions.

## Versions and releases

- `version` in `src/info.plist` is the workflow version. Each release is a `vX.Y.Z` tag on the commit that bumps it, with `airdrop-discoverability.alfredworkflow` (exported from Alfred) plus its `.sha256` and detached `.sig` attached to the GitHub release. The signing commands are in `_stuff/signing.md`, which is gitignored and may be absent from a checkout.
- The tested-macOS list exists twice: README's "Tested Mac OS versions" (``- Mac OS `15.5` Sequoia, workflow version `1.0.0`;``) and the `readme` key in `src/info.plist`, which Alfred displays and which ships in the release (same format without the release name). Update both together. In both, the last item ends with `.` instead of `;`.
- README spells it "Mac OS", puts asides in `(*…*)`, and has a `<!-- MarkdownTOC -->` table of contents (4-space nested items) to update when headings change.
