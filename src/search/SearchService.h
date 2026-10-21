#pragma once

#include <QObject>
#include <QThread>
#include <QVariantList>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <memory>

class QDirIterator;

class DropImportWorker;

class SearchService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString searchRoot READ searchRoot CONSTANT)
    Q_PROPERTY(bool importInProgress READ importInProgress NOTIFY importStateChanged)
    Q_PROPERTY(int importProgressPercent READ importProgressPercent NOTIFY importProgressChanged)
    Q_PROPERTY(QString importStatus READ importStatus NOTIFY importProgressChanged)

public:
    explicit SearchService(QObject *parent = nullptr);
    ~SearchService() override;

    QString searchRoot() const;
    bool importInProgress() const;
    int importProgressPercent() const;
    QString importStatus() const;

    Q_INVOKABLE QVariantMap startNameSearch(const QString &query);
    Q_INVOKABLE QVariantMap nextNameSearchPage();
    Q_INVOKABLE QVariantList listFolderContents(const QString &path) const;
    Q_INVOKABLE bool importDroppedUrls(const QVariantList &urls,
                                       const QString &destinationDirectory = QString());

signals:
    void importStateChanged();
    void importProgressChanged();
    void dropImportFinished(bool succeeded, const QString &message);

private:
    QVariantMap readNextSearchPage();

    QString m_searchRoot;
    QString m_activeSearchQuery;
    QString m_activeSearchRoot;
    std::unique_ptr<QDirIterator> m_searchIterator;
    QVariantMap m_pendingSearchResult;
    bool m_hasPendingSearchResult = false;
    QThread m_importThread;
    DropImportWorker *m_importWorker = nullptr;
    bool m_importInProgress = false;
    int m_importProgressPercent = 0;
    QString m_importStatus;
};
