# Argon Bootstrap

`Bootstrap.exe` is a small native Windows program built independently from Qt. It lives at:

```text
Argon-sim/
  App/Argon.exe
  Bootstrap/Bootstrap.exe
  Updater/ArgonUpdater.exe
  Updates/
    Downloads/
    Staging/
    Backups/
```

## What the first version does

- Opens a real desktop window when double-clicked.
- Fetches `bootstrap-latest.json` over HTTPS and compares four-part versions.
- Shows separate status for Bootstrap and the installed updater.
- Reads `directory.json` only when the installed updater is missing or older than the configured version.
- Does not make changes if metadata is invalid, offline, or lacks a real updater URL, SHA-256, and byte size.
- If a real updater package is later configured, downloads it to a temporary file, checks the declared size and SHA-256, and requires its embedded Windows file version to match the metadata.
- Copies any existing updater to `Updates/Backups` before replacing it. A flushed transaction record allows the next Bootstrap launch to finish verification or restore that backup after an interrupted replacement. Backups are retained after success.

The first metadata record advertises Bootstrap and updater version `1.0.0.0`. The updater package is not published yet: `directory.json` intentionally has an empty `packageUrl`, empty `sha256`, and `sizeBytes: 0`. For now, Bootstrap should report that it is current and that an updater installation/update is pending, without changing updater files.

## Build and test

On the Windows build machine, run `build.bat`. CMake emits `Bootstrap.exe` into a staging directory. The deployment script activates the staged app and bootstrap together and restores the previous folders if activation fails.

To test the current first version:

1. Run `build.bat` and double-click `Desktop/Argon-sim/Bootstrap/Bootstrap.exe`.
2. With internet available, confirm the window reports Bootstrap v`1.0.0.0` as up to date and reports that updater v`1.0.0.0` has no published package.
3. Disconnect networking and launch it again. The window should report that latest status could not be verified; installed files must remain untouched.
4. To test an actual replacement later, publish a real HTTPS updater asset, set its exact SHA-256 and byte length in `directory.json`, and embed the same four-part file version in the updater executable's Windows version resource. Test in a disposable `Argon-sim` folder first.

## Safety boundary

The bootstrap is not the updater. It handles metadata, downloads an updater package if it is fully configured, validates it, and safely stages its executable. Update application logic beyond replacing `ArgonUpdater.exe` belongs in the separate updater project. The current first version does not replace Bootstrap itself.

HTTPS and SHA-256 checks help prevent incomplete or mismatched downloads, but a checksum stored beside its URL is not a digital signature. Production releases should use signed packages and/or signed metadata before distributing automatic updater replacement to users.
