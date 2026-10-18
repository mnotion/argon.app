#pragma once

#include <QObject>
#include <QProcess>
#include <QString>

class UpdaterStatusService final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString installedVersion READ installedVersion NOTIFY stateChanged)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(QString packageStatus READ packageStatus NOTIFY stateChanged)
    Q_PROPERTY(QString details READ details NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotesUrl READ releaseNotesUrl NOTIFY stateChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY stateChanged)
    Q_PROPERTY(bool checkSucceeded READ checkSucceeded NOTIFY stateChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY stateChanged)

public:
    explicit UpdaterStatusService(QObject *parent = nullptr);

    QString installedVersion() const;
    QString latestVersion() const;
    QString status() const;
    QString packageStatus() const;
    QString details() const;
    QString releaseNotesUrl() const;
    bool checking() const;
    bool checkSucceeded() const;
    bool updateAvailable() const;

    Q_INVOKABLE void checkForUpdates();

signals:
    void stateChanged();

private:
    void readStatusFile();
    void failCheck(const QString &message);

    QProcess m_process;
    QString m_rootDirectory;
    QString m_bootstrapPath;
    QString m_statusFilePath;
    QString m_installedVersion;
    QString m_latestVersion;
    QString m_status = QStringLiteral("Updater status has not been checked.");
    QString m_packageStatus = QStringLiteral("Waiting for Bootstrap.");
    QString m_details;
    QString m_releaseNotesUrl;
    bool m_checking = false;
    bool m_checkSucceeded = false;
    bool m_updateAvailable = false;
};
