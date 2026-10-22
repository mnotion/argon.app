#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QString>

class UpdateService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotesUrl READ releaseNotesUrl NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY stateChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY stateChanged)

public:
    explicit UpdateService(QObject *parent = nullptr);

    QString currentVersion() const;
    QString latestVersion() const;
    QString releaseNotesUrl() const;
    QString status() const;
    bool checking() const;
    bool updateAvailable() const;

    Q_INVOKABLE void checkForUpdates();

signals:
    void stateChanged();

private:
    void setStatus(const QString &status);
    static bool isNewerVersion(const QString &candidate, const QString &current);

    QNetworkAccessManager m_network;
    QString m_currentVersion = QStringLiteral("0.1.0-dev");
    QString m_latestVersion;
    QString m_releaseNotesUrl;
    QString m_status = QStringLiteral("Updates have not been checked.");
    bool m_checking = false;
    bool m_updateAvailable = false;
};
