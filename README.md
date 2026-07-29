<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./assets/brand-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="./assets/brand-light.png">
  <img src="./assets/brand-light.png" align="right" width="104" alt="SteepAwake green teacup">
</picture>

# SteepAwake

Keep Windows awake for 30 minutes, 1, 2, 4, or 6 hours—or indefinitely—from
one quiet tray menu. When you are done, SteepAwake restores the sleep settings
you already had.

## Download

- **[SteepAwake-Setup.exe](https://github.com/smkwray/SteepAwake/releases/latest/download/SteepAwake-Setup.exe)**
  is the recommended installer. It installs for the current user, can start
  SteepAwake with Windows, and requires no administrator privileges.
- **[SteepAwake.exe](https://github.com/smkwray/SteepAwake/releases/latest/download/SteepAwake.exe)**
  is the portable single-file build.

Both files and their SHA-256 checksums are available on the
[Releases page](https://github.com/smkwray/SteepAwake/releases).
The binaries are not code-signed, so Windows SmartScreen may ask you to confirm
the first launch.

Fresh installations start in **Normal sleep** mode. Right-click the tray icon
to choose 30 minutes, 1 hour, 2 hours, 4 hours, 6 hours, or Indefinitely.
The same menu contains a **Start with Windows** checkbox. It uses the current
user's startup registry entry and does not cause a User Account Control prompt.

## How it works

When an awake session starts, SteepAwake:

1. reads the active Windows power scheme and saves its plugged-in and battery
   `Sleep after` values;
2. changes both values to `0`, which is Windows' **Never** setting;
3. restores the saved values when the timer expires, Normal sleep is selected,
   or the app exits.

This changes the actual power policy through Windows' `PowrProf` API. It does
not create an execution request, so `powercfg /requests` normally continues to
show `None`.

SteepAwake does not change display timeout, manual sleep, lid-close behavior,
critical-battery actions, router behavior, or application/server idle
timeouts.

Preferences are stored in `%LOCALAPPDATA%\SteepAwake`. The installer places
the app in `%LOCALAPPDATA%\Programs\SteepAwake`.

## Run from source

Requires [AutoHotkey v2](https://www.autohotkey.com/):

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' .\src\SteepAwake.ahk
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
