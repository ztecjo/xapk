# ZTEC XAPK Installer

Windows-only tool to install `.xapk` packages over ADB.

Copyright (c) 2026 ZTEC JO — [MIT License](LICENSE)

## What you need

- Windows 10 / 11
- `adb` from Android [platform-tools](https://developer.android.com/tools/releases/platform-tools) on your PATH
- Device connected with USB debugging on

## How to use

Keep these two files together:

- `install.bat`
- `extract_xapk.ps1`

Drop your `.xapk` in the same folder, then double-click `install.bat`.  
If more than one package is there, it will ask which one. Confirm with Y.

You can also pass a path:

```bat
install.bat "D:\packages\some-app.xapk"
```

OBB / game data is pushed automatically when the package has it.

## Common issues

**adb not found** — install platform-tools and reopen the terminal.

**No device / unauthorized** — check the cable, enable USB debugging, accept the prompt on the device.

**Install failed (signature)** — uninstall the existing app on the device, then run again.
