<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./assets/brand-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./assets/brand-light.png">
  <img src="./assets/brand-light.png" align="right" width="80" alt="SteepAwake green teacup">
</picture>

# SteepAwake

Keep Windows awake for 30 minutes, 1, 2, 4, or 6 hours—or indefinitely—from
one quiet tray menu. When you are done, SteepAwake restores the sleep settings
you already had.

## Download

- **[SteepAwake-Setup.exe](https://github.com/smkwray/SteepAwake/releases/latest/download/SteepAwake-Setup.exe)**
  is the recommended installer. It installs the protected tray component under
  Program Files and asks for administrator approval once during setup.
- **[SteepAwake.exe](https://github.com/smkwray/SteepAwake/releases/latest/download/SteepAwake.exe)**
  is the portable single-file build.

Both files and their SHA-256 checksums are available on the
[Releases page](https://github.com/smkwray/SteepAwake/releases).
The binaries are not code-signed, so Windows SmartScreen may ask you to confirm
the first launch.

Fresh installations start in **Normal sleep** mode. Right-click the tray icon
to choose 30 minutes, 1 hour, 2 hours, 4 hours, 6 hours, or Indefinitely.
The same menu contains a **Start with Windows** checkbox. It starts a small
unelevated launcher, which asks the installed task to start the elevated tray
component. Normal launches and service transitions do not cause another User
Account Control prompt.

Two optional checkboxes apply only while an awake session is active:

- **Keep display active on AC while awake** controls whether SteepAwake holds a
  display-required request and keeps the AC display timeout from reaching the
  device's display-off state. It can be changed while a session is active.
- **Keep awake with lid closed** temporarily changes the AC and battery
  lid-close actions to **Do nothing**. Overriding the battery action matters
  because Windows applies it immediately when AC drops out with the lid
  closed, even for a charger blip of a few seconds. The built-in display still
  turns off when the lid closes. Keep the computer's vents clear when using it
  closed.

The lid option is off by default and normal lid-close behavior remains unchanged
unless you enable it. The display option is off by default and can be toggled
while the session is active.

### Device-specific ASUSOptimization toggle

Some ASUS devices may have an ASUSOptimization service policy that suspends the
system when the lid is closed. The optional **Pause ASUSOptimization during awake
sessions** checkbox is hidden by default because ASUSOptimization also provides
platform features such as keyboard brightness and hotkeys.

To expose this checkbox on an affected device, create
`%LOCALAPPDATA%\SteepAwake\device.ini` with:

```ini
[Device]
EnableAsusOptimizationToggle=1
```

The checkbox is a session preference. When an awake session starts, SteepAwake
records the service's stable state and stops only ASUSOptimization if it was
running. When the session ends through Normal sleep, expiry, Exit, or recovery,
SteepAwake restores the state it owns and verifies the transition. A service that
was already stopped remains stopped. The ASUS System Control Interface driver and
its other services remain installed.

The installer registers one protected interactive task whose only action is to
start the elevated tray component. The launcher and tray coordinate through
per-user named events and a mutex, so a normal click never creates a second tray
instance and never needs to elevate the launcher. ASUSOptimization control is
performed directly by the already-elevated tray process.

## How it works

When an awake session starts, SteepAwake:

1. reads the active Windows power scheme and saves its plugged-in and battery
   sleep, display, and lid-close values;
2. requires AC power, acquires a system-required power request, and optionally
   acquires a display-required request when display protection is enabled;
3. optionally records and pauses ASUSOptimization, with a durable restore
   obligation;
4. restores every saved value and owned service state when the timer expires,
   Normal sleep is selected, the app exits, or a later launch recovers an
   interrupted session.

This uses Windows' `PowerCreateRequest` API, so `powercfg /requests` should show
SteepAwake while an awake session is active. The AC-only timeout fallback and
lid override are restored when the session ends. If Armoury Crate changes the
active power plan during a session, SteepAwake ends that session without
switching back to the old plan.

SteepAwake also watches AC/DC and console display-state notifications. If AC
power is still absent one minute after it drops, the session ends and the
saved settings, including the battery lid action, are restored. If display
protection is enabled and Windows reports
the console display as truly off, the session ends and reports that the
protection precondition was lost; it does not repeatedly fight another
program's explicit monitor-off command. With the option disabled, the display
may turn off while the system-required request remains active. Monitor-off
hotkeys from other programs are not modified or intercepted.

SteepAwake does not block manual sleep or change critical-battery actions,
router behavior, or application/server idle timeouts. The optional display and
lid settings affect only the active Windows power policy and are restored after
the awake session.

Preferences and the recovery journal are stored in `%LOCALAPPDATA%\SteepAwake`.
The installer places the launcher and tray component in the protected
`%ProgramFiles%\SteepAwake` directory.

## Run from source

Requires [AutoHotkey v2](https://www.autohotkey.com/):

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' .\src\SteepAwake.Tray.ahk --task-entry
```

## Build

GitHub Actions builds both release files from pinned, checksum-verified
AutoHotkey, Ahk2Exe, and Inno Setup versions whenever a `v*` tag is pushed.
For a local build, first prepare the same tools:

```powershell
pwsh -NoProfile -File .\scripts\setup-build-tools.ps1
```

Then build:

```powershell
pwsh -NoProfile -File .\scripts\build.ps1
```

Outputs are written to `dist/`:

- `SteepAwake.exe`
- `SteepAwake.Tray.exe`
- `SteepAwake-Setup.exe` when Inno Setup is available
- `SHA256SUMS.txt`

The six light/dark tray icons are reproducibly generated with:

```powershell
pwsh -NoProfile -File .\tools\GenerateIcons.ps1
```

## Validate

```powershell
pwsh -NoProfile -File .\tests\Smoke.ps1
```

## License

SteepAwake source code and artwork are available under the MIT License.
Compiled builds bundle the AutoHotkey runtime; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
