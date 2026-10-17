#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QUrl>

class ReleaseMetadataService final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotesUrl READ releaseNotesUrl NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(QString metadataUrl READ metadataUrl CONSTANT)
    Q_PROPERTY(bool checking READ checking NOTIFY stateChanged)
    Q_PROPERTY(bool checkSucceeded READ checkSucceeded NOTIFY stateChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY stateChanged)

public:
    explicit ReleaseMetadataService(QObject *parent = nullptr);

    QString currentVersion() const;
    QString latestVersion() const;
    QString releaseNotesUrl() const;
    QString status() const;
    QString metadataUrl() const;
    bool checking() const;
    bool checkSucceeded() const;
    bool updateAvailable() const;

    Q_INVOKABLE void checkForUpdates();

signals:
    void stateChanged();

private:
    void failCheck(const QString &message);

    QNetworkAccessManager m_network;
    QString m_currentVersion;
    QUrl m_metadataUrl;
    QString m_latestVersion;
    QString m_releaseNotesUrl;
    QString m_status = QStringLiteral("Updates have not been checked.");
    bool m_checking = false;
    bool m_checkSucceeded = false;
    bool m_updateAvailable = false;
};
