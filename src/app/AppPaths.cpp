#include "AppPaths.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStringList>
#include <QUuid>
#include <QtGlobal>

namespace ArgonPaths
{
namespace
{
QString cleanPath(const QString &path)
{
    return QDir::cleanPath(QDir::fromNativeSeparators(path));
}

QString normalizedPath(const QString &path)
{
    QString result = cleanPath(path);
#ifdef Q_OS_WIN
    result = result.toCaseFolded();
#endif
    return result;
}

bool samePath(const QString &left, const QString &right)
{
    return normalizedPath(left) == normalizedPath(right);
}

bool writeJsonAtomically(const QString &path, const QJsonObject &object)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;

    const QByteArray bytes = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(bytes) != bytes.size()) {
        file.cancelWriting();
        return false;
    }
    return file.commit();
}

bool readJsonObject(const QString &path, QJsonObject &object)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;

    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return false;

    object = document.object();
    return true;
}

bool preserveBrokenFile(const QString &path)
{
    const QString backupPath = path + QStringLiteral(".corrupt-")
        + QUuid::createUuid().toString(QUuid::WithoutBraces);
    return QFile::copy(path, backupPath);
}

bool mergeSettingsFile(const QString &sourcePath,
                       const QString &destinationPath,
                       bool &changed)
{
    changed = false;
    if (!QFileInfo::exists(destinationPath)) {
        if (!QDir().mkpath(QFileInfo(destinationPath).absolutePath()))
            return false;
        changed = QFile::copy(sourcePath, destinationPath);
        return changed;
    }

    QJsonObject sourceRoot;
    if (!readJsonObject(sourcePath, sourceRoot))
        return true; // Keep the original source and destination if either is unreadable.

    QJsonObject destinationRoot;
    if (!readJsonObject(destinationPath, destinationRoot)) {
        // Do not replace an unreadable destination unless its exact bytes were preserved.
        if (!preserveBrokenFile(destinationPath))
            return true;
        changed = writeJsonAtomically(destinationPath, sourceRoot);
        return changed;
    }

    const QJsonValue sourceValuesValue = sourceRoot.value(QStringLiteral("values"));
    if (!sourceValuesValue.isObject())
        return true;
    const QJsonObject sourceValues = sourceValuesValue.toObject();

    QJsonObject destinationValues;
    const QJsonValue destinationValuesValue = destinationRoot.value(QStringLiteral("values"));
    if (destinationValuesValue.isObject())
        destinationValues = destinationValuesValue.toObject();

    // Preserve canonical preferences. Fill missing values from the legacy copy,
    // and specifically keep the greatest saved stopwatch duration so a defaults
    // file created by the duplicate installation cannot reset the user's timer.
    for (auto it = sourceValues.constBegin(); it != sourceValues.constEnd(); ++it) {
        if (!destinationValues.contains(it.key())) {
            destinationValues.insert(it.key(), it.value());
            changed = true;
        }
    }

    const QString elapsedKey = QStringLiteral("timer.elapsedMilliseconds");
    const QString runningKey = QStringLiteral("timer.wasRunning");
    const QJsonValue sourceElapsedValue = sourceValues.value(elapsedKey);
    const QJsonValue destinationElapsedValue = destinationValues.value(elapsedKey);
    const double sourceElapsed = sourceElapsedValue.toDouble(-1.0);
    const double destinationElapsed = destinationElapsedValue.toDouble(-1.0);

    if (sourceElapsed >= 0.0 && sourceElapsed > destinationElapsed) {
        destinationValues.insert(elapsedKey, sourceElapsedValue);
        const QJsonValue sourceRunning = sourceValues.value(runningKey);
        if (!sourceRunning.isUndefined())
            destinationValues.insert(runningKey, sourceRunning);
        changed = true;
    }

    // Retain useful root-level metadata and unknown settings fields as well.
    for (auto it = sourceRoot.constBegin(); it != sourceRoot.constEnd(); ++it) {
        if (it.key() != QStringLiteral("values")
            && !destinationRoot.contains(it.key())) {
            destinationRoot.insert(it.key(), it.value());
            changed = true;
        }
    }

    if (!changed)
        return true;

    destinationRoot.insert(QStringLiteral("values"), destinationValues);
    if (!destinationRoot.contains(QStringLiteral("schemaVersion")))
        destinationRoot.insert(QStringLiteral("schemaVersion"), 1);
    return writeJsonAtomically(destinationPath, destinationRoot);
}

bool mergeDailyAnalyticsFile(const QString &sourcePath,
                             const QString &destinationPath,
                             bool &changed)
{
    changed = false;
    if (!QFileInfo::exists(destinationPath)) {
        if (!QDir().mkpath(QFileInfo(destinationPath).absolutePath()))
            return false;
        changed = QFile::copy(sourcePath, destinationPath);
        return changed;
    }

    QJsonObject source;
    if (!readJsonObject(sourcePath, source))
        return true;

    QJsonObject destination;
    if (!readJsonObject(destinationPath, destination)) {
        if (!preserveBrokenFile(destinationPath))
            return true;
        changed = writeJsonAtomically(destinationPath, source);
        return changed;
    }

    const QString sourceDate = source.value(QStringLiteral("date")).toString();
    const QString destinationDate = destination.value(QStringLiteral("date")).toString();
    if (sourceDate.isEmpty() || sourceDate != destinationDate)
        return true;

    // These are cumulative per-day counters. Taking the maximum avoids both
    // losing a populated record to a newly-created zero record and double-counting
    // the same minutes when both roots contain copies of the same activity.
    const double sourceSeconds = source.value(QStringLiteral("focusedSeconds")).toDouble(0.0);
    const double destinationSeconds = destination.value(QStringLiteral("focusedSeconds")).toDouble(0.0);
    if (sourceSeconds > destinationSeconds) {
        destination.insert(QStringLiteral("focusedSeconds"), sourceSeconds);
        changed = true;
    }

    const int sourceSessions = source.value(QStringLiteral("completedFocusSessions")).toInt(0);
    const int destinationSessions = destination.value(QStringLiteral("completedFocusSessions")).toInt(0);
    if (sourceSessions > destinationSessions) {
        destination.insert(QStringLiteral("completedFocusSessions"), sourceSessions);
        changed = true;
    }

    for (auto it = source.constBegin(); it != source.constEnd(); ++it) {
        if (!destination.contains(it.key())) {
            destination.insert(it.key(), it.value());
            changed = true;
        }
    }

    const QString sourceUpdatedAt = source.value(QStringLiteral("updatedAt")).toString();
    const QString destinationUpdatedAt = destination.value(QStringLiteral("updatedAt")).toString();
    if (sourceUpdatedAt > destinationUpdatedAt) {
        destination.insert(QStringLiteral("updatedAt"), sourceUpdatedAt);
        changed = true;
    }

    if (!changed)
        return true;

    if (!destination.contains(QStringLiteral("schemaVersion")))
        destination.insert(QStringLiteral("schemaVersion"), 1);
    return writeJsonAtomically(destinationPath, destination);
}

QString normalizedLegacyRelativePath(const QString &relativePath, bool legacyLowercaseLayout)
{
    QStringList parts = QDir::fromNativeSeparators(relativePath).split(
        QLatin1Char('/'), Qt::SkipEmptyParts);
    if (!legacyLowercaseLayout || parts.isEmpty())
        return parts.join(QLatin1Char('/'));

    const QString first = parts.at(0).toCaseFolded();
    if (first == QStringLiteral("settings")) parts[0] = QStringLiteral("Settings");
    else if (first == QStringLiteral("cache")) parts[0] = QStringLiteral("Cache");
    else if (first == QStringLiteral("search qr")) parts[0] = QStringLiteral("Search QR");
    else if (first == QStringLiteral("documents")) parts[0] = QStringLiteral("Documents");
    else if (first == QStringLiteral("argon files")) parts[0] = QStringLiteral("Argon Files");
    else if (first == QStringLiteral("accounts")) parts[0] = QStringLiteral("Accounts");
    else if (first == QStringLiteral("analytics")) parts[0] = QStringLiteral("Analytics");

    if (parts.size() > 1
        && parts.at(0) == QStringLiteral("Analytics")
        && parts.at(1).compare(QStringLiteral("daily"), Qt::CaseInsensitive) == 0) {
        parts[1] = QStringLiteral("Daily");
    }
    return parts.join(QLatin1Char('/'));
}

bool copyLegacyDirectoryContents(const QString &sourceDirectoryPath,
                                 const QString &destinationDirectoryPath,
                                 const QString &relativePrefix,
                                 bool legacyLowercaseLayout,
                                 int &changedFiles,
                                 QString *errorMessage)
{
    if (!QDir(sourceDirectoryPath).exists())
        return true;

    QDir sourceDirectory(sourceDirectoryPath);
    const QFileInfoList entries = sourceDirectory.entryInfoList(
        QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
        QDir::Name);

    for (const QFileInfo &entry : entries) {
        // Never follow symlinks while migrating user-controlled data.
        if (entry.isSymLink())
            continue;

        const QString relativePath = relativePrefix.isEmpty()
            ? entry.fileName()
            : relativePrefix + QLatin1Char('/') + entry.fileName();
        const QString mappedRelativePath =
            normalizedLegacyRelativePath(relativePath, legacyLowercaseLayout);
        const QString destinationPath = QDir(destinationDirectoryPath).filePath(
            mappedRelativePath.mid(mappedRelativePath.lastIndexOf(QLatin1Char('/')) + 1));

        if (entry.isDir()) {
            if (!QDir().mkpath(destinationPath)) {
                if (errorMessage)
                    *errorMessage = QStringLiteral("Could not create migrated directory: ") + destinationPath;
                return false;
            }
            if (!copyLegacyDirectoryContents(entry.absoluteFilePath(), destinationPath,
                                             mappedRelativePath, legacyLowercaseLayout,
                                             changedFiles, errorMessage)) {
                return false;
            }
            continue;
        }

        if (!entry.isFile())
            continue;

        // Build the full target using the mapped relative path from the root;
        // destinationDirectoryPath already represents the mapped parent prefix.
        const QString normalizedRelative = mappedRelativePath.toCaseFolded();
        bool changed = false;
        bool okay = true;
        if (normalizedRelative == QStringLiteral("settings/app-settings.json")) {
            okay = mergeSettingsFile(entry.absoluteFilePath(), destinationPath, changed);
        } else if (normalizedRelative.startsWith(QStringLiteral("analytics/daily/"))
                   && normalizedRelative.endsWith(QStringLiteral(".json"))) {
            okay = mergeDailyAnalyticsFile(entry.absoluteFilePath(), destinationPath, changed);
        } else if (!QFileInfo::exists(destinationPath)) {
            if (!QDir().mkpath(QFileInfo(destinationPath).absolutePath())) {
                okay = false;
            } else {
                okay = QFile::copy(entry.absoluteFilePath(), destinationPath);
                changed = okay;
            }
        }

        if (!okay) {
            if (errorMessage)
                *errorMessage = QStringLiteral("Could not preserve legacy user data from ")
                    + entry.absoluteFilePath() + QStringLiteral(" to ") + destinationPath;
            return false;
        }
        if (changed)
            ++changedFiles;
    }

    return true;
}

bool migrateDuplicateUserData(QString *errorMessage)
{
    const QString target = userDataDirectory();
    const QString markerPath = QDir(target).filePath(
        QStringLiteral(".legacy-root-migration-v2"));
    if (QFileInfo::exists(markerPath))
        return true;

    QStringList candidates;
    const QString localAppData = qEnvironmentVariable("LOCALAPPDATA").trimmed();
    const QString explicitRoot = qEnvironmentVariable("ARGON_DATA_ROOT").trimmed();
    const QString canonicalRoot = localAppData.isEmpty()
        ? QString()
        : cleanPath(QDir(localAppData).filePath(QStringLiteral("Argon-sim")));

    // The old run.bat used the Desktop copy while build.bat deployed to
    // LocalAppData. Prefer the prior Argon-sim data tree when present. Explicit
    // isolated roots are kept isolated from the Desktop user's real files.
    if (explicitRoot.isEmpty()) {
        const QString desktop = QStandardPaths::writableLocation(
            QStandardPaths::DesktopLocation);
        if (!desktop.isEmpty())
            candidates.append(QDir(desktop).filePath(
                QStringLiteral("Argon-sim/UserData")));
    }

    // An explicit, isolated test root must not import a developer's real files.
    // Duplicate-root recovery runs only when the active root is canonical
    // Argon-sim (or when no override was supplied).
    const bool canonicalContext = explicitRoot.isEmpty()
        || (!canonicalRoot.isEmpty() && samePath(rootDirectory(), canonicalRoot));
    if (!explicitRoot.isEmpty() && !canonicalRoot.isEmpty()
        && canonicalContext && !samePath(explicitRoot, canonicalRoot)) {
        const QString overrideName = QFileInfo(explicitRoot).fileName();
        if (overrideName.compare(QStringLiteral("Argon"), Qt::CaseInsensitive) == 0
            || overrideName.compare(QStringLiteral("Argon-sim"), Qt::CaseInsensitive) == 0) {
            candidates.append(QDir(explicitRoot).filePath(QStringLiteral("UserData")));
        }
    }
    if (!localAppData.isEmpty() && canonicalContext) {
        candidates.append(QDir(localAppData).filePath(QStringLiteral("Argon/UserData")));
        candidates.append(QDir(localAppData).filePath(QStringLiteral("Argon/user-data")));
    }

    int changedFiles = 0;
    bool foundLegacyRoot = false;
    for (const QString &candidate : candidates) {
        if (!QDir(candidate).exists() || samePath(candidate, target))
            continue;

        foundLegacyRoot = true;
        const bool legacyLowercaseLayout =
            QFileInfo(candidate).fileName().compare(QStringLiteral("user-data"),
                                                      Qt::CaseInsensitive) == 0;
        QString migrationError;
        if (!copyLegacyDirectoryContents(candidate, target, QString(), legacyLowercaseLayout,
                                         changedFiles, &migrationError)) {
            if (errorMessage)
                *errorMessage = migrationError;
            qWarning().noquote() << "[DataMigration]" << migrationError
                                 << "Original files have been retained.";
            return false;
        }
    }

    if (foundLegacyRoot) {
        QSaveFile marker(markerPath);
        const QByteArray markerContents("completed\n");
        if (!marker.open(QIODevice::WriteOnly | QIODevice::Text)
            || marker.write(markerContents) != markerContents.size()
            || !marker.commit()) {
            if (errorMessage)
                *errorMessage = QStringLiteral("Could not write user-data migration marker: ")
                    + markerPath;
            qWarning().noquote() << "[DataMigration] Could not write migration marker:"
                                 << markerPath;
            return false;
        }
    }

    if (changedFiles > 0) {
        qInfo().noquote() << "[DataMigration] Restored" << changedFiles
                          << "legacy user-data file(s) into" << target
                          << "(all source files were retained).";
    }
    return true;
}
} // namespace

QString rootDirectory()
{
    // ARGON_DATA_ROOT is reserved for explicit development/test deployments.
    // Normal Windows builds always share the single canonical Argon-sim root,
    // even when a downloaded executable is launched from a temporary or old
    // installation folder. This prevents a second %LOCALAPPDATA%/Argon tree.
    const QString overrideRoot = qEnvironmentVariable("ARGON_DATA_ROOT").trimmed();
    if (!overrideRoot.isEmpty()) {
        const QFileInfo overrideInfo(overrideRoot);
        const QString absolutePath = cleanPath(overrideInfo.isAbsolute()
            ? overrideRoot
            : QDir::current().absoluteFilePath(overrideRoot));
#ifdef Q_OS_WIN
        const QString localAppData = qEnvironmentVariable("LOCALAPPDATA").trimmed();
        if (!localAppData.isEmpty()) {
            const QString canonicalRoot = cleanPath(
                QDir(localAppData).filePath(QStringLiteral("Argon-sim")));
            const QString overrideName = QFileInfo(absolutePath).fileName();
            // Keep arbitrary temporary roots available for automated tests, but
            // do not honor a stale launcher override to either old Argon root or
            // a second Argon-sim folder. Migrate that folder into the canonical one.
            const bool isArgonDataRoot =
                overrideName.compare(QStringLiteral("Argon"), Qt::CaseInsensitive) == 0
                || overrideName.compare(QStringLiteral("Argon-sim"), Qt::CaseInsensitive) == 0;
            if (isArgonDataRoot && !samePath(absolutePath, canonicalRoot))
                return canonicalRoot;
        }
#endif
        return absolutePath;
    }

#ifdef Q_OS_WIN
    const QString localAppData = qEnvironmentVariable("LOCALAPPDATA").trimmed();
    if (!localAppData.isEmpty())
        return cleanPath(QDir(localAppData).filePath(QStringLiteral("Argon-sim")));

    // Match build.bat's fallback if the LOCALAPPDATA environment variable is
    // unavailable; do not silently move data to the Roaming profile.
    return cleanPath(QDir(QDir::homePath()).filePath(
        QStringLiteral("AppData/Local/Argon-sim")));
#else
    const QString genericData = QStandardPaths::writableLocation(
        QStandardPaths::GenericDataLocation);
    if (!genericData.isEmpty())
        return cleanPath(QDir(genericData).filePath(QStringLiteral("Argon-sim")));

    return cleanPath(QDir(QDir::homePath()).filePath(
        QStringLiteral(".local/share/Argon-sim")));
#endif
}

QString appDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("App")); }
QString updaterDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("Updater")); }
QString bootstrapDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("Bootstrap")); }

// Persistent user files intentionally live beside App rather than inside it.
// The updater replaces App/Argon.exe and must never replace this directory.
QString userDataDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("UserData")); }
QString settingsDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Settings")); }
QString cacheDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Cache")); }
QString searchRootDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Search QR")); }
QString documentsDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Documents")); }
QString argonFilesDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Argon Files")); }
QString accountsDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Accounts")); }
QString analyticsDirectory()
{
    return QDir(userDataDirectory()).filePath(QStringLiteral("Analytics/Daily"));
}

QString updatesDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("Updates")); }
QString downloadsDirectory() { return QDir(updatesDirectory()).filePath(QStringLiteral("Downloads")); }
QString stagingDirectory() { return QDir(updatesDirectory()).filePath(QStringLiteral("Staging")); }
QString backupsDirectory() { return QDir(updatesDirectory()).filePath(QStringLiteral("Backups")); }

QString logsDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("Logs")); }
QString runtimeLogFilePath() { return QDir(logsDirectory()).filePath(QStringLiteral("argon-runtime.log")); }

bool ensureDirectoryStructure(QString *errorMessage)
{
    const QStringList requiredDirectories = {
        rootDirectory(),
        appDirectory(),
        updaterDirectory(),
        bootstrapDirectory(),
        userDataDirectory(),
        settingsDirectory(),
        cacheDirectory(),
        searchRootDirectory(),
        documentsDirectory(),
        argonFilesDirectory(),
        accountsDirectory(),
        analyticsDirectory(),
        updatesDirectory(),
        downloadsDirectory(),
        stagingDirectory(),
        backupsDirectory(),
        logsDirectory()
    };

    QStringList failures;
    for (const QString &path : requiredDirectories) {
        if (!QDir().mkpath(path))
            failures.append(path);
    }

    if (failures.isEmpty()) {
        QString migrationError;
        if (!migrateDuplicateUserData(&migrationError) && !migrationError.isEmpty())
            failures.append(migrationError);
    }

    if (errorMessage) {
        *errorMessage = failures.isEmpty()
            ? QString()
            : QStringLiteral("Could not fully prepare Argon runtime paths: ")
                + failures.join(QStringLiteral(", "));
    }
    return failures.isEmpty();
}
} // namespace ArgonPaths
