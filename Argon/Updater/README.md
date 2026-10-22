# Updater payload

Reserved for `ArgonUpdater.exe`. The executable is not committed here yet because the separate `argon-updater` project must implement and build it first.

The initial installer should refuse to create a distributable package if the required updater binary is missing; an empty placeholder is not a substitute for a real executable.
