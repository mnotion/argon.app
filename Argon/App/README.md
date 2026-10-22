# Application payload

This directory is reserved for the installed `Argon.exe`, Qt runtime libraries, plugins, and packaged resources.

During development, `run.bat` launches `build/Argon.exe` directly and uses this repository-local `Argon/` tree only as its writable data root. Generated binaries are not committed to this directory. Inno Setup will populate this folder in an installed build.
