#pragma once

#include <QObject>
#include <QStringList>

class DropImportWorker final : public QObject
{
    Q_OBJECT

public:
    explicit DropImportWorker(QObject *parent = nullptr);

public slots:
    void copyItems(QStringList sourcePaths, QString destinationDirectory);

signals:
    void progressChanged(const QString &currentItem,
                         qint64 copiedBytes,
                         qint64 totalBytes,
                         int completedFiles,
                         int totalFiles);
    void copyCompleted(int importedCount, int failedCount, const QString &message);
};
