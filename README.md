# Argon — native app

## Stack
- **Frontend:** Qt Quick / QML
- **Core and performance-sensitive code:** C++20
- **Build:** CMake and Qt's CMake integration
- **Initial target:** Windows 64-bit, Qt 6.12.0, MinGW 13.1.0

## Run locally
The scripts expect Qt at `C:\Qt\6.12.0\mingw_64` and MinGW at `C:\Qt\Tools\mingw1310_64`.
Double-click `build.bat` to compile Argon and deploy the runnable application plus Qt dependencies to the Desktop's `Argon-sim\App` folder. This is the only script that compiles the app or deploys its Qt dependencies. CMake object files and other intermediates remain in the repository's `build\` directory; the runnable executable is written to desktop staging and then activated under `Argon-sim\App`.
Double-click `run.bat` to launch the already-deployed test copy. It does not invoke CMake, compile, or deploy dependencies; if the test copy does not exist yet, it tells you to run `build.bat` first. Test data, user data, and logs stay under the Desktop's `Argon-sim\` folder.

## Architecture
- `src/app/`: application-wide services and lifecycle integration.
- `src/versioning/`: strict three-part version parsing/comparison and latest-release metadata lookup.
- `src/documents/`: document domain and document operations.
- `src/ink/`: reserved for the dedicated stylus/ink engine.
- `src/pdf/`: reserved for PDF integration.
- `src/services/`: reserved for cross-cutting services.
- `qml/components/`: reusable visual controls.
- `qml/pages/`: individual workspace screens.
- `qml/themes/`: central visual tokens.
- `qml/Main.qml`: application shell and page composition.

QML owns presentation and UI interaction. C++ owns application logic and performance-sensitive functionality. Keep components independently testable and avoid putting filesystem, database or document logic into UI files.

## Per-user directory layout

At startup, Argon creates its writable runtime layout under `%LOCALAPPDATA%\Argon` on Windows. The directory path is centralized in `src/app/AppPaths.*`. When launched through `run.bat`, Argon sets `ARGON_DATA_ROOT` to the repository's `Argon/` folder so the exact same layout can be tested without changing the real per-user data. Packaged builds leave this override unset.

```text
%LOCALAPPDATA%\Argon\
├── App\                 # Installed Argon executable and Qt files (installer-owned)
├── Updater\             # ArgonUpdater.exe (added by updater packaging)
├── Bootstrap\           # ArgonBootstrap.exe (added by updater packaging)
├── UserData\
│   ├── Settings\
│   ├── Cache\
│   ├── Search QR\      # Search and explorer share this root
│   ├── Documents\
│   ├── Accounts\
│   └── Analytics\Daily\
├── Updates\
│   ├── Downloads\
│   ├── Staging\
│   └── Backups\
└── Logs\                # Includes argon-runtime.log
```

The application provisions folders but does not copy its own executable into `App\`; the installer will own installation of binaries. Existing Search QR content and daily analytics are copied non-destructively from their previous locations when found. Original files are retained, existing destination files are never overwritten, and migration markers prevent repeated copying.

## Status
The modular shell provisions the runtime directory layout through `AppPaths`. Normal Windows launches use `%LOCALAPPDATA%\Argon`; `run.bat` overrides the root to the repository's `Argon/` folder for development testing. Search content, runtime logs, and daily analytics use the centralized paths. One-time, non-destructive migrations preserve legacy files. Settings persistence, document storage, updater binaries, bootstrap binaries, and ink rendering remain in progress. Build and runtime validation are required after each milestone.


## Versioning

The current app version is defined once in the CMake project version (`0.1.0`) and exposed through `QCoreApplication::applicationVersion()` and `AppServices.version`. Versions currently use strict `MAJOR.MINOR.PATCH` form only. Components are compared numerically, so `1.10.0` is newer than `1.9.0`; suffixes such as `-dev` are intentionally not accepted in this first versioning milestone.

`src/versioning/ReleaseMetadataService.*` fetches and validates `latest.json` asynchronously. It only discovers version information; it does not download or install updates. The default metadata URL is in `src/versioning/ReleaseMetadataService.cpp`. Override it for development with `ARGON_LATEST_JSON_URL`. `latest.json` is published in the public `argon.updater` repository, so installed clients can fetch it anonymously over HTTPS. Keep credentials out of Argon; the metadata contains only public release information.

### Run the offline versioning tests

From PowerShell at the repository root:

```powershell
cmake -S . -B build-version-tests -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH="C:\Qt\6.12.0\mingw_64" -DCMAKE_CXX_COMPILER="C:\Qt\Tools\mingw1310_64\bin\g++.exe" -DCMAKE_MAKE_PROGRAM="C:\Qt\Tools\mingw1310_64\bin\mingw32-make.exe" -DARGON_BUILD_VERSIONING_TESTS=ON
cmake --build build-version-tests --target ArgonVersioningTests --parallel
ctest --test-dir build-version-tests --output-on-failure
```

These tests do not require network access and do not modify the normal `build/` directory used by `build.bat`.
