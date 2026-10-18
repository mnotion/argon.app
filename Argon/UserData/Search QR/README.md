# Argon Search QR data

This is the development test dataset root for Argon's local search and explorer features. Installed builds use the corresponding directory under `%LOCALAPPDATA%\\Argon\\UserData\\Search QR`.

## Search contract

- Search recursively through this folder and its subdirectories.
- Match queries against file names and supported text content.
- Treat matching as case-insensitive.
- Return only files inside this search root; do not search the rest of the computer.
- Skip symlinks and unsafe/unreadable entries.
- Never modify, rename, or delete indexed files.
- Search remains local. File contents are not uploaded.

## Supported content

File/folder names are indexed for all readable entries. Text extraction currently supports `.txt`, `.md`, `.csv`, `.json`, `.xml`, `.html`, `.htm`, `.qml`, `.cpp`, `.h`, `.py`, and `.log`. Other file types may appear as filename matches; their internal content requires a dedicated extractor.
