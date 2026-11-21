# Reading the AirDrop state for the Script Filter

Evidence behind the Script Filter rules in `CLAUDE.md`. These are the measurements and the sources that didn't work, so they aren't retried blind.

## Probe on Mac OS 27.2.1 (2026-11-21)

`debugging/probe-airdrop-state.py` ran every candidate source with AirDrop set to Contacts Only, in three states: everything on, Bluetooth off from the Menu Bar, and Bluetooth back on with Wi-Fi off. Timings are wall-clock per call as measured from Python.

| Source | All on | Bluetooth off | Wi-Fi off | Time |
|---|---|---|---|---|
| `defaults read com.apple.sharingd DiscoverableMode` | `Contacts Only` | `Contacts Only` | `Contacts Only` | 7–10 ms |
| `defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState` | key missing (exit 1) | key missing | key missing | 6–8 ms |
| `system_profiler SPBluetoothDataType -json` → `controller_state` | `attrib_on` | `attrib_off` | `attrib_on` | 76–114 ms |
| the same → `controller_discoverable` | `attrib_off` | `attrib_off` | `attrib_off` | |
| `ioreg -l -w0`, keys naming both Bluetooth and power | none | none | none | ~250 ms |
| `networksetup -listallhardwareports` → device of `Hardware Port: Wi-Fi` | `en0` | `en0` | `en0` | 20–24 ms |
| `networksetup -getairportpower en0` | `On` | `On` | `Off` | 19–20 ms |
| whole `com.apple.sharingd` domain | — | identical to all on | identical to all on | ~10 ms |

What the UI showed (user-observed):

- With Bluetooth off, the AirDrop panel said Off and Finder said No One, although `DiscoverableMode` still said `Contacts Only`. With Wi-Fi off, the panel and Finder said the same.
- When Bluetooth came back on, the level returned to Contacts Only by itself. Nobody has checked yet whether it does the same when Wi-Fi comes back on.

Conclusions:

- **`ControllerPowerState` is gone on 27.2.1, and `ioreg` has no usable key**, which leaves `system_profiler` as the Bluetooth source.
- **`controller_discoverable` is Bluetooth's own discoverability**, `attrib_off` in every state, so it says nothing about AirDrop.
- **No other key in the sharingd domain changes between the states**, so the effective level could only be derived from `DiscoverableMode` plus the two radios.

## Dropped variants (2026-11-21)

Both were implemented and tested with fakes in the container. The user then dropped them in favour of a bare `DiscoverableMode` and a "(current level)" subtitle on the matching option, to keep the workflow simple.

- **A status row above the options.** It was a non-actionable "Currently: <level>" row, shown only on an empty query so that the highlighted row stays actionable. That forced the script to filter the options itself with `alfredfiltersresults` off (see the Alfred section below), so Alfred reran the script on every keystroke.
- **Radio checks.** For a stored Contacts Only or Everyone the filter showed No One whenever a radio was off:
  - Bluetooth: `system_profiler SPBluetoothDataType -json` reporting `"controller_state"` `attrib_off`;
  - Wi-Fi: `networksetup -getairportpower` on the device under `Hardware Port: Wi-Fi` reporting `: Off`.

  The subtitle then named the radio and the stored level, e.g. "Bluetooth is off, Contacts Only once it's back on". A check that failed counted as on. Together the checks cost about 0.15 s per run, and with the self-filtering that meant about 0.15 s per keystroke.

## Alfred

- **"Alfred filters results" runs the script only once.** The [Script Filter docs](https://www.alfredapp.com/help/workflows/inputs/script-filter/) say: "scripts run _once_ and every additional typed character reduces results from the full initial output". With that option the query never reaches the script, so a status row that hides on a query can't work. The JSON `match` field could have narrowed what Alfred matches, but the [JSON docs](https://www.alfredapp.com/help/workflows/inputs/script-filter/json/) don't say what an empty `match` does. That is why the dropped status-row variant filtered in the script. Without a status row, Alfred's own filtering is fine.
- **`skipknowledge` stops new learning only.** Per the JSON docs it "prevents the creation of new knowledge but does not ignore what Alfred already learned". The items carry no `uid` either, so Alfred has nothing to learn from.
- **Script type numbers aren't documented by Alfred:**
  - `5` is plain `/bin/zsh`, which reads `~/.zshenv`.
  - `11` is `/bin/zsh --no-rcs`, Alfred's default shell since 5.1.2. That number is inferred from other workflows, e.g. [a launcher's PR that runs Alfred workflows](https://github.com/estrenuo/Reach/pull/6). Opening the workflow in Alfred's editor confirms it: the Language field must say `/bin/zsh --no-rcs`.
