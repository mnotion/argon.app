#include "AppPaths.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QStringList>
#include <QtGlobal>

namespace ArgonPaths
{
namespace
{
QString cleanPath(const QString &path)
{
    return QDir::cleanPath(QDir::fromNativeSeparators(path));
}
}

QString rootDirectory()
{
    // The run.bat development launcher sets this override to the checked-in
    // Argon/ folder so the runtime layout can be tested without touching the
    // real per-user installation data. Packaged launches leave it unset.
    const QString overrideRoot = qEnvironmentVariable(
        "ARGON_DATA_ROOT").trimmed();
    if (!overrideRoot.isEmpty()) {
        const QFileInfo overrideInfo(overrideRoot);
        const QString absolutePath = overrideInfo.isAbsolute()
            ? overrideRoot
            : QDir::current().absoluteFilePath(overrideRoot);
        return cleanPath(absolutePath);
    }

#ifdef Q_OS_WIN
    const QString localAppData = qEnvironmentVariable("LOCALAPPDATA");
    if (!localAppData.trimmed().isEmpty())
        return cleanPath(QDir(localAppData).filePath(QStringLiteral("Argon")));
#endif

    const QString appLocalData = QStandardPaths::writableLocation(
        QStandardPaths::AppLocalDataLocation);
    if (!appLocalData.isEmpty()) {
        const QString normalized = cleanPath(appLocalData);
        if (QFileInfo(normalized).fileName().compare(
                QStringLiteral("Argon"), Qt::CaseInsensitive) == 0) {
            return normalized;
        }
        return cleanPath(QDir(normalized).filePath(QStringLiteral("Argon")));
    }

    return cleanPath(QDir(QDir::homePath()).filePath(
        QStringLiteral(".local/share/Argon")));
}

QString appDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("App")); }
QString updaterDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("Updater")); }
QString bootstrapDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("Bootstrap")); }

QString userDataDirectory() { return QDir(rootDirectory()).filePath(QStringLiteral("UserData")); }
QString settingsDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Settings")); }
QString cacheDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Cache")); }
QString searchRootDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Search QR")); }
QString documentsDirectory() { return QDir(userDataDirectory()).filePath(QStringLiteral("Documents")); }
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

    if (errorMessage) {
        *errorMessage = failures.isEmpty()
            ? QString()
            : QStringLiteral("Could not create required Argon directories: ")
                + failures.join(QStringLiteral(", "));
    }
    return failures.isEmpty();
}
} // namespace ArgonPaths
