# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An [Alfred](https://alfredapp.com) workflow that sets AirDrop discoverability (No One / Contacts Only / Everyone) by clicking through the macOS UI via Accessibility from AppleScript, since macOS offers no API for it. There is no build system, linter or test suite. All logic is one AppleScript embedded as a string in `src/info.plist`; `src/` as a whole is the workflow folder (`info.plist`, `icon.png`, `List Filter Images/`).

Nothing here can run in the container: there is no `osascript`, `osacompile`, `plutil` or Alfred on Linux, and the script's behaviour depends on the live macOS UI. A behavioural change is unverified until the user runs it on a Mac, so say that rather than claiming it works. The working tree is the user's Mac checkout, so files written to the gitignored `_stuff/` reach the Mac as they are, and output the user saves there can be read back here.

## Commands

```sh
# the only check available in the container: the plist still parses
python3 -c 'import plistlib; plistlib.load(open("src/info.plist", "rb"))'

# extract the embedded AppleScript unescaped, for reading, diffing or running on the Mac
python3 -c 'import plistlib; print(next(o["config"]["script"] for o in plistlib.load(open("src/info.plist", "rb"))["objects"] if o["type"] == "alfred.workflow.action.script"))' > _stuff/airdrop.applescript
```

The user runs these on the Mac from the repo folder (the terminal app needs Accessibility permission):

```sh
# one level (1 No One, 2 Contacts Only, 3 Everyone) without Alfred; the variable must be set, because "" as integer throws
TOGGLE_OFF_BLUETOOTH=0 osascript _stuff/airdrop.applescript 2

# Accessibility tree of everything the script clicks through, for adapting to a new Mac OS version
osascript debugging/dump-airdrop-ui.applescript agents finder > _stuff/ui-dump.txt 2>&1
```

- Each route needs its own run: the Menu Bar routes run only while the AirDrop or Bluetooth icon is on the Menu Bar, and the Finder and Control Centre fallbacks only while it isn't.
- Panel contents depend on state, so dump in the state that shows the controls. For example, the AirDrop panel lists its level checkboxes only while AirDrop is on.
- `debugging/dump-airdrop-ui.applescript` changes no settings; it only opens panels and closes them with ESC. Its `agents` section matches the Mac OS 27 layout, and `menubar` the layout up to Mac OS 26.
- The dump script is tracked, but **its output is not**: it holds the user's name, Bluetooth device addresses, volume and server names and the process list. Always write dumps to the gitignored `_stuff/`, and never quote them in files that get committed. Paths and identifiers of Apple's own controls are fine to quote.
- Host-side syntax checks that click nothing: `plutil -lint src/info.plist`, and `osacompile -o <tmp>.scpt _stuff/airdrop.applescript`.

## Architecture

`src/info.plist` is an Alfred object graph wired by UID in `connections` (`uidata` holds only editor-canvas positions):

1. keyword `airdrop` (`alfred.workflow.input.keyword`) →
2. list filter (`alfred.workflow.input.listfilter`) whose `items` is a JSON string mapping No One / Contacts Only / Everyone to arg `1` / `2` / `3`, each with an icon referenced by file name from `src/List Filter Images/` →
3. script action (`alfred.workflow.action.script`, `type` 6 = AppleScript, `scriptargtype` 1 = argv) receiving that arg.

The level number doubles as the UI ordinal: `checkbox <level>` in the AirDrop panel (`checkbox 1` is the on/off toggle) and `menu item <level>` of Finder's "Allow me to be discovered by" pop-up. The 1/2/3 mapping therefore follows macOS's own control order and can't be renumbered on its own.

Script flow:

1. `run` → `applyDiscoverabilityLevel` (validates 1–3) → `toggleAirDropViaMenuBar`.
2. `toggleAirDropViaMenuBar` calls `clickMenuBarIcon("com.apple.menuextra.airdrop")` and works in the panel that opens, `window "Control Centre"` of process `ControlCenter`.
3. If anything in that `try` fails (e.g. no AirDrop icon on the Menu Bar), it ends up in `toggleAirDropViaFinder`: new Finder window, ⇧⌘R, `pop up button 1 of group 1 of splitter group 1 of splitter group 1 of window 1`, then `menu item <level> of menu 1` of it.
4. The Control Centre route between the two deliberately just throws, because Control Centre's AirDrop options are not reachable through Accessibility.
5. Afterwards, for level 1 with the user-configuration checkbox `TOGGLE_OFF_BLUETOOTH` set (declared in `userconfigurationconfig`, read via `system attribute`), `toggleBluetoothOff` runs:
   - it clicks the Bluetooth icon (`com.apple.menuextra.bluetooth`) and its panel's `checkbox 1 of group 1`;
   - otherwise, it opens Control Centre (`com.apple.menuextra.controlcenter`) and toggles the module that `findControlCentreModule("controlcenter-bluetooth")` returns;
   - if neither works, it errors.

Mac OS 27 layout, as found on 27.2.1 (the old paths are commented out in the script with dated notes):

- Apple's Menu Bar icons belong to process `MenuBarAgent`, each as `menu bar item 1` of its own `group` of `menu bar 1`. They have no description but do have an `AXIdentifier` (`com.apple.menuextra.airdrop`, `.bluetooth`, `.controlcenter`, …), so find them with `clickMenuBarIcon`, never by description or position. `ControlCenter` has no menu bar anymore but still owns the panels.
- In the full Control Centre every module is a group of its own (`group N of group 1`), so find a module by its toggle's identifier with `findControlCentreModule`, not by group number.
- In Finder, address the dropdown as `pop up button 1`, never as `button N`: with Bluetooth off, the same group also has an unlabelled `button 1` (Turn on Bluetooth).
- Controls that appear after a click or keystroke go through `waitForElement` (up to 3 s) before they are touched.

## Editing rules

- Edit `src/info.plist` as text. The script is XML-escaped inside its `<string>`, so `>` / `<` / `&` are written `&gt;` / `&lt;` / `&amp;` (see `argc &gt; 1`, `" &amp; ex`). Don't write the file back through `plistlib.dump`: it reformats the `uidata` reals (`<real>145</real>` → `145.0`), a spurious diff. Re-run the parse check after every edit.
- The plist structure is indented with tabs (Alfred's output); the AppleScript body uses 4 spaces.
- UI paths are mostly ordinals (`group 1 of splitter group 1 of window 1`), because most controls have no IDs or labels. They break with macOS updates, which is the usual reason to touch this code. Where an `AXIdentifier` exists and ordinals would be ambiguous, find the element by identifier instead. `window "Control Centre"` is matched literally, so keep the British spelling.
- The script supports one Mac OS major version at a time (27.x as of `2026.11.21`). When the UI changes, replace the paths rather than adding fallbacks for the previous version, and comment the old code out with a dated note, as the script already does. Users of an older Mac OS stay on the workflow version the tested-versions list gives for it.
- Keep the commented-out blocks and long comments in the script; they record approaches that stopped working on specific macOS versions.

## Versions and releases

- `version` in `src/info.plist` is the workflow version. It is date-based (`YYYY.MM.DD`) from `2026.11.21` on; earlier releases were `0.9.1` to `1.0.0`. Each release so far is a `v<version>` tag on the commit that bumps it, with `airdrop-discoverability.alfredworkflow` (exported from Alfred) plus its `.sha256` and detached `.sig` attached to the GitHub release. The signing commands are in `_stuff/signing.md`, which is gitignored and may be absent from a checkout.
- The tested-macOS list exists twice: README's "Tested Mac OS versions" (``- Mac OS `27.2.1` Golden Gate, workflow version `2026.11.21`.``) and the `readme` key in `src/info.plist`, which Alfred displays and which ships in the release (same format without the release name). Update both together. In both, the last item ends with `.` instead of `;`.
- README spells it "Mac OS", puts asides in `(*…*)`, and has a `<!-- MarkdownTOC -->` table of contents (4-space nested items) to update when headings change.
