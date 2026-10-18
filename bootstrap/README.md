# Argon Bootstrap

Argon Bootstrap is a small native Windows companion. It is not the updater, and it does not update itself. Its version-checking responsibility is the installed ArgonUpdater.exe.

## Runtime layout

```text
Argon-sim/
  App/Argon.exe
  Bootstrap/Bootstrap.exe
  Updater/ArgonUpdater.exe
  Updates/
    Downloads/
    Staging/
    Backups/
    Status/updater-status.json
```

## Version ownership

- ArgonUpdater.exe embeds its four-part Windows FileVersion and ProductVersion in its VERSIONINFO resource.
- Bootstrap reads that installed file version with the Windows version API.
- Bootstrap fetches bootstrap-latest.json from the stable metadata branch and compares its updaterVersion field with the installed ArgonUpdater.exe version.
- bootstrapVersion remains compatibility metadata for the Bootstrap binary and is not used as the installed updater version.
- Argon launches Bootstrap with --background. Bootstrap performs the check, writes a status JSON under Updates/Status, and exits without opening a second window. It only replaces Updater/ArgonUpdater.exe when the user explicitly approves an available update in the Argon UI (or presses Install update in the standalone Bootstrap window).
- Launching Bootstrap manually opens the readable Argon-styled status window.

## Current updater target

The repository builds a deliberately inert ArgonUpdater.exe target whose embedded file and product versions are 1.0.0.0. It exits immediately and contains no update behaviour. Its purpose is to provide a real PE version resource that Bootstrap can read; later updater functionality belongs in a separately tested release.

The current release metadata advertises updater 1.0.0.0. No downloadable updater asset has been published yet. directory.json therefore intentionally leaves packageUrl and sha256 empty and sizeBytes set to 0. Bootstrap must not replace a file until a real HTTPS asset, exact SHA-256, exact byte length, and matching embedded version are published.

## Build and test

On the Windows build machine, run build.bat. It builds Argon, the Bootstrap companion, and the inert updater version 1.0.0.0. The updater is emitted into Argon-sim/Updater/ArgonUpdater.exe.

1. Confirm the built executable's Details tab shows File version 1.0.0.0.
2. Launch Argon.exe. It starts Bootstrap in the background; the Account menu's Updates card should show both Argon release status and updater version status.
3. Launch Bootstrap.exe manually to see the standalone status window.
4. To test a version mismatch, change updaterVersion in bootstrap-latest.json. Bootstrap should report it in the Argon menu without changing any files. The Install updater update action only becomes available when directory.json points to a real package with matching version, HTTPS URL, checksum, and byte size.
5. Test offline handling in a disposable Argon-sim folder. Offline status must be marked unverified and must not be presented as a live successful check.

## Safety

Bootstrap only modifies Updater/ArgonUpdater.exe; it keeps temporary downloads, backups, and recovery records beneath Updates. Before replacement, it validates HTTPS transport, exact byte size, SHA-256, and the executable's embedded version. Existing updaters are backed up before atomic replacement and verified after installation.

A checksum stored alongside its package URL is not a digital signature. Production releases should also authenticate signed packages and/or signed metadata.
