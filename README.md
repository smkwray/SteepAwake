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

Two optional checkboxes apply only while an awake session is active:

- **Keep display on while awake** temporarily disables the display timeout.
- **Keep awake with lid closed** temporarily changes the lid-close action to
  **Do nothing**. The built-in display still turns off when the lid closes.
  Keep the computer's vents clear when using it closed.

Both options are off by default. Normal display timeout and lid-close behavior
remain unchanged unless you enable them.

## How it works

When an awake session starts, SteepAwake:

1. creates a Windows system power request that prevents automatic sleep without
   changing the power plan's sleep timeout;
2. adds a display power request if that option is enabled and temporarily
   changes the lid-close action only if its separate option is enabled;
3. releases the requests and restores any changed lid setting when the timer
   expires, Normal sleep is selected, or the app exits.

The request is scoped to the running app and appears in `powercfg /requests`
while an awake session is active. Normal sleep and display timeouts are never
rewritten. When upgrading from version 0.2, SteepAwake first restores any power
policy saved by an active legacy session.

On Modern Standby laptops, Windows can limit application power requests after
the display turns off while running on battery. Timed and indefinite sessions
are therefore best-effort on battery; plugged-in requests remain active until
SteepAwake clears them. See Microsoft's
[Modern Standby guidance](https://learn.microsoft.com/windows-hardware/design/device-experiences/prepare-software-for-modern-standby).

SteepAwake does not block manual sleep or change critical-battery actions,
router behavior, or application/server idle timeouts. The optional lid setting
affects only the active Windows power policy and is restored after the awake
session.

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
