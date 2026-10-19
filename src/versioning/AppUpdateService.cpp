#include "AppUpdateService.h"

#include "../app/AppPaths.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QProcess>
#include <QTimer>

AppUpdateService::AppUpdateService(QObject *parent)
    : QObject(parent)
{
    // Use the same canonical root as settings, analytics, and the native updater.
    m_rootDirectory = ArgonPaths::rootDirectory();
    m_updaterPath = QDir(ArgonPaths::updaterDirectory()).filePath(
        QStringLiteral("ArgonUpdater.exe"));
    m_statusFilePath = QDir(ArgonPaths::updatesDirectory()).filePath(
        QStringLiteral("Status/app-update-status.json"));

    QDir().mkpath(QFileInfo(m_statusFilePath).absolutePath());

    connect(&m_process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
                consumeStatusFile();
                if (m_state == QStringLiteral("downloading")) {
                    const QString detail = exitStatus == QProcess::CrashExit
                        ? QStringLiteral("ArgonUpdater stopped unexpectedly.")
                        : QStringLiteral("ArgonUpdater exited with code %1 without completing the download.")
                              .arg(exitCode);
                    launchFailure(detail);
                }
            });
    connect(&m_process, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError processError) {
                if (processError == QProcess::FailedToStart)
                    launchFailure(QStringLiteral("Could not start ArgonUpdater.exe."));
            });

    m_pollTimer.setInterval(160);
    connect(&m_pollTimer, &QTimer::timeout,
            this, &AppUpdateService::pollStatusFile);
    m_pollTimer.start();
    consumeStatusFile();
}

QString AppUpdateService::state() const { return m_state; }
QString AppUpdateService::status() const { return m_status; }
QString AppUpdateService::targetVersion() const { return m_targetVersion; }
QString AppUpdateService::error() const { return m_error; }
int AppUpdateService::progress() const { return m_progress; }
bool AppUpdateService::downloading() const { return m_state == QStringLiteral("downloading"); }
bool AppUpdateService::downloaded() const { return m_state == QStringLiteral("downloaded"); }
bool AppUpdateService::installing() const { return m_state == QStringLiteral("installing"); }

void AppUpdateService::setState(const QString &state, const QString &status,
                                const QString &error)
{
    const bool changed = m_state != state || m_status != status
        || m_error != error;
    m_state = state;
    m_status = status;
    m_error = error;
    if (state == QStringLiteral("downloaded"))
        m_progress = 100;
    if (state == QStringLiteral("downloading") && m_progress < 0)
        m_progress = 0;
    if (changed)
        emit stateChanged();
}

void AppUpdateService::downloadUpdate(const QString &expectedVersion)
{
    if (m_process.state() != QProcess::NotRunning || installing())
        return;

    m_targetVersion = expectedVersion.trimmed();
    if (m_targetVersion.isEmpty()) {
        launchFailure(QStringLiteral("The latest Argon version has not been resolved yet."));
        return;
    }
    if (!QFileInfo::exists(m_updaterPath)) {
        launchFailure(QStringLiteral("ArgonUpdater.exe was not found at %1.").arg(m_updaterPath));
        return;
    }

    QFile::remove(m_statusFilePath);
    m_progress = 0;
    m_error.clear();
    setState(QStringLiteral("downloading"),
             QStringLiteral("Preparing secure download of Argon %1…").arg(m_targetVersion));

    m_process.setProgram(m_updaterPath);
    m_process.setArguments({
        QStringLiteral("--download-only"),
        QStringLiteral("--expected-version"), m_targetVersion,
        QStringLiteral("--status-file"), m_statusFilePath
    });
    m_process.setWorkingDirectory(m_rootDirectory);
    m_process.start();
}

void AppUpdateService::installUpdate()
{
    if (!downloaded() || m_targetVersion.isEmpty())
        return;
    if (!QFileInfo::exists(m_updaterPath)) {
        launchFailure(QStringLiteral("ArgonUpdater.exe was not found at %1.").arg(m_updaterPath));
        return;
    }

    QFile::remove(m_statusFilePath);
    const QStringList arguments{
        QStringLiteral("--install-downloaded"),
        QStringLiteral("--expected-version"), m_targetVersion,
        QStringLiteral("--status-file"), m_statusFilePath
    };
    if (!QProcess::startDetached(m_updaterPath, arguments, m_rootDirectory)) {
        launchFailure(QStringLiteral("Could not start the Argon update installation."));
        return;
    }

    setState(QStringLiteral("installing"),
             QStringLiteral("Installing Argon %1. The app will restart automatically…")
                 .arg(m_targetVersion));
    QTimer::singleShot(450, QCoreApplication::instance(), []() {
        QCoreApplication::quit();
    });
}

void AppUpdateService::pollStatusFile()
{
    if (m_state == QStringLiteral("installing") || m_state == QStringLiteral("installed"))
        consumeStatusFile();
    else if (m_process.state() != QProcess::NotRunning)
        consumeStatusFile();
}

void AppUpdateService::consumeStatusFile()
{
    QFile file(m_statusFilePath);
    if (!file.open(QIODevice::ReadOnly))
        return;

    const QByteArray statusBytes = file.readAll();
    file.close();
    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(statusBytes, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return;

    const QJsonObject object = document.object();
    const QString nextState = object.value(QStringLiteral("state")).toString();
    if (nextState.isEmpty())
        return;

    const QString nextStatus = object.value(QStringLiteral("status")).toString();
    const QString nextError = object.value(QStringLiteral("error")).toString();
    const int nextProgress = qBound(0, object.value(QStringLiteral("progress")).toInt(m_progress), 100);
    const QString nextVersion = object.value(QStringLiteral("version")).toString();
    if (!nextVersion.isEmpty())
        m_targetVersion = nextVersion;
    const bool progressChanged = m_progress != nextProgress;
    m_progress = nextProgress;
    const QString oldState = m_state;
    const QString oldStatus = m_status;
    const QString oldError = m_error;
    setState(nextState, nextStatus.isEmpty() ? m_status : nextStatus, nextError);
    if (progressChanged && oldState == m_state && oldStatus == m_status && oldError == m_error)
        emit stateChanged();
    if (nextState == QStringLiteral("installed")) {
        QFile::remove(m_statusFilePath);
        m_pollTimer.stop();
    }
}

void AppUpdateService::launchFailure(const QString &message)
{
    setState(QStringLiteral("failed"), message, message);
}
