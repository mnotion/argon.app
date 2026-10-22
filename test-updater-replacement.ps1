$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSCommandPath
$sourceRoot = Join-Path $env:LOCALAPPDATA "Argon-sim"
$sourceBootstrap = Join-Path $sourceRoot "Bootstrap\Bootstrap.exe"

if (-not (Test-Path -LiteralPath $sourceBootstrap)) {
    throw "Working Bootstrap not found at '$sourceBootstrap'. Build the working deployment first."
}

$qtRoot = "C:\Qt\6.12.0\mingw_64"
$mingwRoot = "C:\Qt\Tools\mingw1310_64"
$buildDir = Join-Path $repoRoot "build"
$cmake = (Get-Command cmake.exe -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath (Join-Path $qtRoot "lib\cmake\Qt6\Qt6Config.cmake"))) {
    throw "Qt 6.12 CMake files were not found at '$qtRoot'."
}
if (-not (Test-Path -LiteralPath (Join-Path $mingwRoot "bin\g++.exe"))) {
    throw "MinGW compiler was not found at '$mingwRoot'."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$testRoot = Join-Path $env:LOCALAPPDATA "Argon-updater-test-$timestamp"
$bootstrapDir = Join-Path $testRoot "Bootstrap"
$updaterDir = Join-Path $testRoot "Updater"
$updatesDir = Join-Path $testRoot "Updates"

# A unique test root keeps the known-good Argon-sim deployment untouched.
New-Item -ItemType Directory -Path $bootstrapDir -Force | Out-Null
New-Item -ItemType Directory -Path $updaterDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $updatesDir "Downloads") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $updatesDir "Staging") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $updatesDir "Backups") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $testRoot "Logs") -Force | Out-Null

Copy-Item -LiteralPath $sourceBootstrap -Destination (Join-Path $bootstrapDir "Bootstrap.exe")

$env:PATH = "$mingwRoot\bin;$qtRoot\bin;$env:PATH"

# Build only the inert updater placeholder with a deliberately older PE version.
# The existing Bootstrap and installed Argon-sim tree are not modified.
$qtCmake = $qtRoot.Replace("\", "/")
$mingwCmake = $mingwRoot.Replace("\", "/")
$updaterCmake = $updaterDir.Replace("\", "/")
$configureArgs = @(
    "-S", $repoRoot,
    "-B", $buildDir,
    "-G", "MinGW Makefiles",
    "-DCMAKE_PREFIX_PATH=$qtCmake",
    "-DCMAKE_CXX_COMPILER=$mingwCmake/bin/g++.exe",
    "-DCMAKE_MAKE_PROGRAM=$mingwCmake/bin/mingw32-make.exe",
    "-DARGON_UPDATER_OUTPUT_DIR=$updaterCmake",
    "-DARGON_UPDATER_VERSION=0.9.0.0"
)

Write-Host "=== Configuring isolated updater test ==="
Write-Host "Test root: $testRoot"
& $cmake @configureArgs
if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed." }

Write-Host "=== Building test updater v0.9.0.0 ==="
& $cmake --build $buildDir --target ArgonUpdater --parallel
if ($LASTEXITCODE -ne 0) { throw "ArgonUpdater test build failed." }

$testUpdater = Join-Path $updaterDir "ArgonUpdater.exe"
if (-not (Test-Path -LiteralPath $testUpdater)) {
    throw "Test updater was not produced at '$testUpdater'."
}

$builtVersion = (Get-Item -LiteralPath $testUpdater).VersionInfo.FileVersion
if ($builtVersion -ne "0.9.0.0") {
    throw "Expected test updater 0.9.0.0, but build produced '$builtVersion'."
}

Write-Host "=== Starting isolated Bootstrap ==="
Write-Host "Bootstrap should offer v1.0.0.0. Click Install update, wait for completion, then close the window."
$process = Start-Process -FilePath (Join-Path $bootstrapDir "Bootstrap.exe") -PassThru
Wait-Process -Id $process.Id

Write-Host "=== Verifying updater replacement ==="
$installedUpdater = Join-Path $updaterDir "ArgonUpdater.exe"
$version = (Get-Item -LiteralPath $installedUpdater).VersionInfo.FileVersion
$hash = (Get-FileHash -LiteralPath $installedUpdater -Algorithm SHA256).Hash
$expectedHash = "25E2FA89C420B59D0C154CFF97B8BA49063F20EA987F8BD50732E47555A48295"
$backupDir = Join-Path $updatesDir "Backups"
$backups = @(Get-ChildItem -LiteralPath $backupDir -Filter "ArgonUpdater-*.exe" -File -ErrorAction SilentlyContinue)
$journal = Join-Path $updatesDir "Staging\updater-replacement.pending"

[PSCustomObject]@{
    TestRoot = $testRoot
    InstalledVersion = $version
    InstalledSha256 = $hash
    BackupCount = $backups.Count
    JournalRemains = Test-Path -LiteralPath $journal
} | Format-List

if ($version -ne "1.0.0.0") {
    throw "Replacement test did not finish on v1.0.0.0. Test files were left in '$testRoot' for inspection."
}
if ($hash -ne $expectedHash) {
    throw "Installed file hash does not match the published v1.0.0.0 package. Test files were left in '$testRoot'."
}
if ($backups.Count -lt 1) {
    throw "Replacement completed without retaining the expected old-updater backup. Test files were left in '$testRoot'."
}
if (Test-Path -LiteralPath $journal) {
    throw "Replacement journal still exists after completion. Test files were left in '$testRoot'."
}

Write-Host "=== Testing recovery from an interrupted replacement ==="
$oldBackup = $backups |
    Where-Object { (Get-Item -LiteralPath $_.FullName).VersionInfo.FileVersion -eq "0.9.0.0" } |
    Select-Object -First 1
if (-not $oldBackup) {
    throw "The retained backup is not the expected v0.9.0.0 updater; recovery test was not run."
}
$oldHash = (Get-FileHash -LiteralPath $oldBackup.FullName -Algorithm SHA256).Hash

# Simulate a crash after the transaction journal is durable but the target is incomplete.
$journalText = @"
schemaVersion=1
hadExisting=1
backupFile=$($oldBackup.Name)
originalSha256=$oldHash
expectedSha256=$expectedHash
expectedVersion=1.0.0.0
"@
[System.IO.File]::WriteAllText($journal, $journalText, [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText(
    $installedUpdater,
    "intentionally corrupted bytes in isolated test folder",
    [System.Text.Encoding]::ASCII
)

Write-Host "Running Bootstrap in background to trigger pending-transaction recovery..."
$recovery = Start-Process -FilePath (Join-Path $bootstrapDir "Bootstrap.exe") -ArgumentList "--background" -PassThru -Wait

$recoveredVersion = (Get-Item -LiteralPath $installedUpdater).VersionInfo.FileVersion
$recoveredHash = (Get-FileHash -LiteralPath $installedUpdater -Algorithm SHA256).Hash
[PSCustomObject]@{
    RecoveryVersion = $recoveredVersion
    MatchesBackupHash = ($recoveredHash -eq $oldHash)
    JournalRemains = Test-Path -LiteralPath $journal
} | Format-List

if ($recoveredVersion -ne "0.9.0.0" -or $recoveredHash -ne $oldHash) {
    throw "Recovery did not restore the verified v0.9.0.0 backup. Test files remain at '$testRoot'."
}
if (Test-Path -LiteralPath $journal) {
    throw "Recovery restored the updater but failed to clear the journal. Test files remain at '$testRoot'."
}

Write-Host "PASS: package replacement succeeded, then interrupted-transaction recovery restored the exact original updater."
Write-Host "Isolated test files remain at: $testRoot"
