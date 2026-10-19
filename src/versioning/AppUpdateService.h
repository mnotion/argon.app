#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>

class AppUpdateService final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString status READ status NOTIFY stateChanged)
    Q_PROPERTY(QString targetVersion READ targetVersion NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY stateChanged)
    Q_PROPERTY(bool downloaded READ downloaded NOTIFY stateChanged)
    Q_PROPERTY(bool installing READ installing NOTIFY stateChanged)

public:
    explicit AppUpdateService(QObject *parent = nullptr);

    QString state() const;
    QString status() const;
    QString targetVersion() const;
    QString error() const;
    int progress() const;
    bool downloading() const;
    bool downloaded() const;
    bool installing() const;

    Q_INVOKABLE void downloadUpdate(const QString &expectedVersion);
    Q_INVOKABLE void installUpdate();

signals:
    void stateChanged();

private:
    void setState(const QString &state, const QString &status,
                  const QString &error = QString());
    void pollStatusFile();
    void consumeStatusFile();
    void launchFailure(const QString &message);

    QProcess m_process;
    QTimer m_pollTimer;
    QString m_rootDirectory;
    QString m_updaterPath;
    QString m_statusFilePath;
    QString m_state = QStringLiteral("idle");
    QString m_status = QStringLiteral("Waiting for an update.");
    QString m_targetVersion;
    QString m_error;
    int m_progress = 0;
};
