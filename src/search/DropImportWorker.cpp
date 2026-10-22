#include "DropImportWorker.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <functional>
#include <QSet>
#include <QVector>

namespace {
struct DirectoryEntry
{
    QString destinationPath;
};

struct FileEntry
{
    QString sourcePath;
    QString destinationPath;
    qint64 size = 0;
};

struct ImportPlan
{
    QString displayName;
    QString destinationRoot;
    bool isDirectory = false;
    QVector<DirectoryEntry> directories;
    QVector<FileEntry> files;
};

QString normalizedPath(QString path)
{
    path = QDir::cleanPath(QDir::fromNativeSeparators(path));
#ifdef Q_OS_WIN
    path = path.toCaseFolded();
#endif
    return path;
}

bool pathIsInsideOrEqual(const QString &candidate, const QString &root)
{
    const QString normalizedCandidate = normalizedPath(candidate);
    const QString normalizedRoot = normalizedPath(root);
    return normalizedCandidate == normalizedRoot
        || normalizedCandidate.startsWith(normalizedRoot + QLatin1Char('/'));
}

QString uniqueDestinationPath(const QString &destinationDirectory,
                              const QString &sourceName,
                              bool isDirectory,
                              QSet<QString> &reservedNames)
{
    const QFileInfo sourceInfo(sourceName);
    const QString suffix = isDirectory ? QString() : sourceInfo.suffix();
    const QString baseName = isDirectory ? sourceName : sourceInfo.completeBaseName();

    for (int number = 1; ; ++number) {
        QString candidateName = sourceName;
        if (number > 1) {
            const QString indexedBase = baseName + QStringLiteral(" (")
                + QString::number(number) + QLatin1Char(')');
            candidateName = suffix.isEmpty()
                ? indexedBase
                : indexedBase + QLatin1Char('.') + suffix;
        }

        const QString candidatePath = QDir(destinationDirectory).filePath(candidateName);
        const QString reservationKey = normalizedPath(candidatePath);
        if (!QFileInfo::exists(candidatePath) && !reservedNames.contains(reservationKey)) {
            reservedNames.insert(reservationKey);
            return candidatePath;
        }
    }
}

bool isSafeSource(const QFileInfo &info, const QString &sourcePath, const QString &destinationRoot)
{
    if (!info.exists() || info.isSymLink() || (!info.isFile() && !info.isDir()))
        return false;

    // Do not import items already inside the destination, or a parent folder
    // containing the destination. Both cases could recursively copy Argon into itself.
    if (pathIsInsideOrEqual(sourcePath, destinationRoot))
        return false;
    if (info.isDir() && pathIsInsideOrEqual(destinationRoot, sourcePath))
        return false;

    return true;
}

bool copyFileInChunks(const FileEntry &entry,
                      qint64 &copiedBytes,
                      qint64 totalBytes,
                      int completedFiles,
                      int totalFiles,
                      const std::function<void(const QString &, qint64, qint64, int, int)> &reportProgress)
{
    if (!QDir().mkpath(QFileInfo(entry.destinationPath).absolutePath()))
        return false;

    QFile input(entry.sourcePath);
    QFile output(entry.destinationPath);
    if (!input.open(QIODevice::ReadOnly))
        return false;
    if (!output.open(QIODevice::WriteOnly | QIODevice::NewOnly))
        return false;

    constexpr qint64 chunkSize = 1024 * 1024;
    const qint64 reportInterval = qMax<qint64>(
        chunkSize, totalBytes > 0 ? totalBytes / 100 : chunkSize);
    qint64 lastReportedBytes = copiedBytes;

    while (!input.atEnd()) {
        const QByteArray buffer = input.read(chunkSize);
        if (buffer.isEmpty() && input.error() != QFile::NoError) {
            output.close();
            QFile::remove(entry.destinationPath);
            return false;
        }

        if (!buffer.isEmpty()) {
            const qint64 written = output.write(buffer);
            if (written != buffer.size()) {
                output.close();
                QFile::remove(entry.destinationPath);
                return false;
            }
            copiedBytes += written;
        }

        if (copiedBytes - lastReportedBytes >= reportInterval) {
            reportProgress(QFileInfo(entry.sourcePath).fileName(),
                           copiedBytes, totalBytes, completedFiles, totalFiles);
            lastReportedBytes = copiedBytes;
        }
    }

    output.close();
    input.close();
    if (output.error() != QFile::NoError) {
        QFile::remove(entry.destinationPath);
        return false;
    }
    return true;
}
}

DropImportWorker::DropImportWorker(QObject *parent)
    : QObject(parent)
{
}

void DropImportWorker::copyItems(QStringList sourcePaths, QString destinationDirectory)
{
    emit progressChanged(QStringLiteral("Preparing files…"), 0, 0, 0, 0);

    if (!QDir().mkpath(destinationDirectory)) {
        emit copyCompleted(0, sourcePaths.size(),
                           QStringLiteral("Could not open the destination folder."));
        return;
    }

    const QString destinationRoot = QFileInfo(destinationDirectory).canonicalFilePath();
    if (destinationRoot.isEmpty()) {
        emit copyCompleted(0, sourcePaths.size(),
                           QStringLiteral("Could not resolve the destination folder."));
        return;
    }

    QVector<ImportPlan> plans;
    QSet<QString> seenSources;
    QSet<QString> reservedNames;
    qint64 totalBytes = 0;
    int totalFiles = 0;
    int rejectedCount = 0;

    for (const QString &rawSourcePath : sourcePaths) {
        const QFileInfo rawInfo(rawSourcePath);
        const QString sourcePath = rawInfo.canonicalFilePath();
        if (sourcePath.isEmpty() || !isSafeSource(rawInfo, sourcePath, destinationRoot)) {
            ++rejectedCount;
            continue;
        }

        const QString sourceKey = normalizedPath(sourcePath);
        if (seenSources.contains(sourceKey)) {
            ++rejectedCount;
            continue;
        }
        seenSources.insert(sourceKey);

        ImportPlan plan;
        plan.displayName = rawInfo.fileName();
        plan.isDirectory = rawInfo.isDir();
        plan.destinationRoot = uniqueDestinationPath(
            destinationRoot, plan.displayName, plan.isDirectory, reservedNames);

        if (plan.isDirectory) {
            plan.directories.append({plan.destinationRoot});

            QDirIterator iterator(sourcePath,
                                  QDir::AllEntries | QDir::NoDotAndDotDot
                                      | QDir::Hidden | QDir::System,
                                  QDirIterator::Subdirectories);
            const QDir sourceRoot(sourcePath);
            while (iterator.hasNext()) {
                const QString childPath = iterator.next();
                const QFileInfo childInfo(childPath);
                if (childInfo.isSymLink())
                    continue;

                const QString relativePath = sourceRoot.relativeFilePath(childInfo.absoluteFilePath());
                const QString targetPath = QDir(plan.destinationRoot).filePath(relativePath);
                if (childInfo.isDir()) {
                    plan.directories.append({targetPath});
                } else if (childInfo.isFile()) {
                    const qint64 size = qMax<qint64>(0, childInfo.size());
                    plan.files.append({childInfo.absoluteFilePath(), targetPath, size});
                    totalBytes += size;
                    ++totalFiles;
                }
            }
        } else {
            const qint64 size = qMax<qint64>(0, rawInfo.size());
            plan.files.append({sourcePath, plan.destinationRoot, size});
            totalBytes += size;
            ++totalFiles;
        }

        plans.append(plan);
    }

    if (plans.isEmpty()) {
        emit copyCompleted(0, qMax(rejectedCount, sourcePaths.size()),
                           QStringLiteral("No supported files or folders to import."));
        return;
    }

    qint64 copiedBytes = 0;
    int completedFiles = 0;
    int importedCount = 0;
    int failedCount = rejectedCount;
    const auto reportProgress = [this](const QString &name,
                                       qint64 copied,
                                       qint64 total,
                                       int completed,
                                       int fileCount) {
        emit progressChanged(name, copied, total, completed, fileCount);
    };

    for (const ImportPlan &plan : plans) {
        bool success = true;
        bool destinationRootCreated = false;

        if (plan.isDirectory) {
            // mkdir (not mkpath) ensures a concurrent name collision is never
            // treated as a directory this worker owns and may later remove.
            destinationRootCreated = QDir(destinationRoot).mkdir(QFileInfo(plan.destinationRoot).fileName());
            success = destinationRootCreated;

            for (qsizetype i = 1; success && i < plan.directories.size(); ++i) {
                if (!QDir().mkpath(plan.directories.at(i).destinationPath))
                    success = false;
            }
        }

        if (success) {
            for (const FileEntry &file : plan.files) {
                if (!copyFileInChunks(file, copiedBytes, totalBytes,
                                      completedFiles, totalFiles, reportProgress)) {
                    success = false;
                    break;
                }
                ++completedFiles;
                const int fileProgressInterval = qMax(1, totalFiles / 100);
                if (completedFiles % fileProgressInterval == 0
                    || completedFiles == totalFiles) {
                    reportProgress(QFileInfo(file.sourcePath).fileName(),
                                   copiedBytes, totalBytes, completedFiles, totalFiles);
                }
            }
        }

        if (success) {
            ++importedCount;
        } else {
            ++failedCount;
            if (plan.isDirectory && destinationRootCreated)
                QDir(plan.destinationRoot).removeRecursively();
            // Failed single-file copies remove only partial files created by
            // copyFileInChunks; never delete a pre-existing collision.
        }
    }

    reportProgress(QStringLiteral("Finishing…"), totalBytes, totalBytes, totalFiles, totalFiles);

    QString message;
    if (failedCount == 0) {
        message = importedCount == 1
            ? QStringLiteral("Import complete")
            : QStringLiteral("Import complete");
    } else if (importedCount > 0) {
        message = QStringLiteral("Imported ")
            + QString::number(importedCount)
            + QStringLiteral(" item(s); ")
            + QString::number(failedCount)
            + QStringLiteral(" could not be imported.");
    } else {
        message = QStringLiteral("Could not import the selected items.");
    }

    emit copyCompleted(importedCount, failedCount, message);
}
