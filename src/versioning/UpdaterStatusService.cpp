#include "UpdaterStatusService.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QJsonObject>

UpdaterStatusService::UpdaterStatusService(QObject *parent)
    : QObject(parent)
{
    QDir appDirectory(QCoreApplication::applicationDirPath());
    appDirectory.cdUp();
    m_rootDirectory = QDir::cleanPath(appDirectory.absolutePath());
    m_bootstrapPath = QDir(m_rootDirectory).filePath(
        QStringLiteral("Bootstrap/Bootstrap.exe"));
    m_statusFilePath = QDir(m_rootDirectory).filePath(
        QStringLiteral("Updates/Status/updater-status.json"));

    connect(&m_process,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this,
            [this](int, QProcess::ExitStatus) {
                readStatusFile();
            });
    connect(&m_process, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError error) {
                if (error == QProcess::FailedToStart) {
                    failCheck(QStringLiteral(
                        "Bootstrap.exe could not be started. Rebuild or restore the Bootstrap companion."));
                }
            });
}

QString UpdaterStatusService::installedVersion() const { return m_installedVersion; }
QString UpdaterStatusService::latestVersion() const { return m_latestVersion; }
QString UpdaterStatusService::status() const { return m_status; }
QString UpdaterStatusService::packageStatus() const { return m_packageStatus; }
QString UpdaterStatusService::details() const { return m_details; }
QString UpdaterStatusService::releaseNotesUrl() const { return m_releaseNotesUrl; }
bool UpdaterStatusService::checking() const { return m_checking; }
bool UpdaterStatusService::checkSucceeded() const { return m_checkSucceeded; }
bool UpdaterStatusService::updateAvailable() const { return m_updateAvailable; }
bool UpdaterStatusService::packageAvailable() const { return m_packageAvailable; }

void UpdaterStatusService::checkForUpdates()
{
    startCheck(false);
}

void UpdaterStatusService::installUpdate()
{
    if (!m_checkSucceeded || !m_updateAvailable || !m_packageAvailable) {
        failCheck(QStringLiteral(
            "No verified updater package is available to install. Check for updates again first."));
        return;
    }
    startCheck(true);
}

void UpdaterStatusService::startCheck(bool installUpdater)
{
    if (m_checking || m_process.state() != QProcess::NotRunning)
        return;

    m_checking = true;
    m_checkSucceeded = false;
    m_status = installUpdater
        ? QStringLiteral("Installing the approved Argon Updater release...")
        : QStringLiteral("Checking installed ArgonUpdater.exe against stable metadata...");
    m_packageStatus = installUpdater
        ? QStringLiteral("Downloading and validating the approved updater package.")
        : QStringLiteral("Bootstrap is checking the updater package.");
    m_details.clear();
    emit stateChanged();

    if (!QFileInfo::exists(m_bootstrapPath)) {
        failCheck(QStringLiteral("Bootstrap.exe was not found at %1.").arg(m_bootstrapPath));
        return;
    }

    const QString statusDirectory = QFileInfo(m_statusFilePath).absolutePath();
    if (!QDir().mkpath(statusDirectory)) {
        failCheck(QStringLiteral("Could not create the updater status directory."));
        return;
    }
    QFile::remove(m_statusFilePath);

    m_process.setProgram(m_bootstrapPath);
    QStringList arguments{QStringLiteral("--background")};
    if (installUpdater)
        arguments.append(QStringLiteral("--install-update"));
    m_process.setArguments(arguments);
    m_process.setWorkingDirectory(m_rootDirectory);
    m_process.start();
}

void UpdaterStatusService::readStatusFile()
{
    QFile file(m_statusFilePath);
    if (!file.open(QIODevice::ReadOnly)) {
        failCheck(QStringLiteral(
            "Bootstrap finished without writing a status file. Check the Bootstrap runtime log or launch it manually."));
        return;
    }

    QJsonParseError parseError{};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        failCheck(QStringLiteral("Bootstrap returned unreadable updater status JSON."));
        return;
    }

    const QJsonObject object = document.object();
    if (object.value(QStringLiteral("schemaVersion")).toInt(-1) != 1) {
        failCheck(QStringLiteral("Bootstrap returned an unsupported updater status schema."));
        return;
    }

    m_checkSucceeded = object.value(QStringLiteral("checkSucceeded")).toBool(false);
    m_updateAvailable = object.value(QStringLiteral("updateAvailable")).toBool(false);
    m_packageAvailable = object.value(QStringLiteral("packageAvailable")).toBool(false);
    m_installedVersion = object.value(QStringLiteral("installedVersion")).toString();
    m_latestVersion = object.value(QStringLiteral("latestVersion")).toString();
    m_status = object.value(QStringLiteral("status")).toString(
        QStringLiteral("Bootstrap did not provide a version status."));
    m_packageStatus = object.value(QStringLiteral("packageStatus")).toString(
        QStringLiteral("Bootstrap did not provide a package status."));
    m_details = object.value(QStringLiteral("details")).toString();
    m_releaseNotesUrl = object.value(QStringLiteral("releaseNotesUrl")).toString();
    m_checking = false;
    emit stateChanged();
}

void UpdaterStatusService::failCheck(const QString &message)
{
    m_checking = false;
    m_checkSucceeded = false;
    m_updateAvailable = false;
    m_packageAvailable = false;
    m_status = message;
    m_packageStatus = QStringLiteral("No updater change was requested by Argon.");
    emit stateChanged();
}
