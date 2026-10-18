# Argon — native app

## Stack
- **Frontend:** Qt Quick / QML
- **Core and performance-sensitive code:** C++20
- **Build:** CMake and Qt's CMake integration
- **Initial target:** Windows 64-bit, Qt 6.12.0, MinGW 13.1.0

## Run locally
The scripts expect Qt at `C:\Qt\6.12.0\mingw_64` and MinGW at `C:\Qt\Tools\mingw1310_64`.
Double-click `build.bat` to compile Argon and deploy the runnable application plus Qt dependencies to `%LOCALAPPDATA%\Argon-sim\App`. This is the only script that compiles the app or deploys its Qt dependencies. CMake object files and other intermediates remain in the repository's `build\` directory; the runnable executable is written to staging and then activated under the canonical `Argon-sim\App`.
Double-click `run.bat` to build and launch Argon. Both scripts use `%LOCALAPPDATA%\Argon-sim`; the launcher no longer selects a separate Desktop copy. User data and logs remain beside `App` under the same root.

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

On Windows, all normal builds and updates use the single canonical runtime root `%LOCALAPPDATA%\Argon-sim`. Settings, timer state, daily focus records, documents, search files, and logs live there, outside the replaceable `App` directory. The app and updater services resolve this root through `src/app/AppPaths.*`, rather than deriving different roots from the executable launch location.

Older test builds may have written data under `%LOCALAPPDATA%\Argon\UserData`, `%LOCALAPPDATA%\Argon\user-data`, or the previous Desktop `Argon-sim\UserData` folder. Startup merges missing files into the canonical root without deleting the source files. When matching settings or daily analytics already exist, migration preserves canonical preferences while restoring the larger saved timer duration and daily focus counters instead of letting a zero-value file reset them.

```text
%LOCALAPPDATA%\Argon-sim\
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

The application provisions folders but does not copy its own executable into `App\`; the deployment script owns the runnable binaries. Legacy user data is migrated non-destructively: original files are retained, canonical files are merged without overwriting preferences, and a marker prevents repeated migration.

## Status
The modular shell provisions the runtime directory layout through `AppPaths`. Normal Windows launches and the development scripts use `%LOCALAPPDATA%\Argon-sim` as the single runtime root. Search content, settings, timer state, daily analytics, update status, and logs resolve through centralized paths. Legacy data is merged non-destructively, with originals retained. A Windows build and end-to-end update test are required before treating this fix as verified.


## Versioning

The current app version is defined once in the CMake project version (`0.1.3`) and exposed through `QCoreApplication::applicationVersion()` and `AppServices.version`. Versions currently use strict `MAJOR.MINOR.PATCH` form only. Components are compared numerically, so `1.10.0` is newer than `1.9.0`; suffixes such as `-dev` are intentionally not accepted in this first versioning milestone.

`src/versioning/ReleaseMetadataService.*` fetches and validates `latest.json` asynchronously. It only discovers version information; it does not download or install updates. The default metadata URL is in `src/versioning/ReleaseMetadataService.cpp`. Override it for development with `ARGON_LATEST_JSON_URL`. `latest.json` is published in the public `argon.updater` repository, so installed clients can fetch it anonymously over HTTPS. Keep credentials out of Argon; the metadata contains only public release information.

### Run the offline versioning tests

From PowerShell at the repository root:

```powershell
cmake -S . -B build-version-tests -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH="C:\Qt\6.12.0\mingw_64" -DCMAKE_CXX_COMPILER="C:\Qt\Tools\mingw1310_64\bin\g++.exe" -DCMAKE_MAKE_PROGRAM="C:\Qt\Tools\mingw1310_64\bin\mingw32-make.exe" -DARGON_BUILD_VERSIONING_TESTS=ON
cmake --build build-version-tests --parallel
ctest --test-dir build-version-tests --output-on-failure
```

These tests do not require network access and do not modify the normal `build/` directory used by `build.bat`. The build command compiles both `ArgonVersioningTests` and `ArgonUserSettingsTests` before CTest runs them.
