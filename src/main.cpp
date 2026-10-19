#include <QGuiApplication>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QCoreApplication>
#include <QFile>
#include <QSaveFile>
#include <QUrl>
#include <QDateTime>
#include <QMutex>
#include <QMutexLocker>
#include <QTextStream>
#include <QTimer>
#include <QStringList>
#include <cstdio>

#include "app/AppPaths.h"
#include "app/AppServices.h"
#include "app/UserSettingsService.h"
#include "analytics/DailyAnalyticsService.h"
#include "documents/DocumentService.h"
#include "search/SearchService.h"
#include "versioning/ReleaseMetadataService.h"
#include "versioning/AppUpdateService.h"
#include "versioning/UpdaterStatusService.h"

namespace {
QMutex logMutex;

void writeRuntimeLog(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    QMutexLocker locker(&logMutex);
    const char *level = "INFO";
    switch (type) {
    case QtDebugMsg: level = "DEBUG"; break;
    case QtInfoMsg: level = "INFO"; break;
    case QtWarningMsg: level = "WARNING"; break;
    case QtCriticalMsg: level = "CRITICAL"; break;
    case QtFatalMsg: level = "FATAL"; break;
    }

    const QByteArray consoleMessage = message.toLocal8Bit();
    std::fprintf(stderr, "[%s] %s", level, consoleMessage.constData());
    if (context.file)
        std::fprintf(stderr, " (%s:%d)", context.file, context.line);
    std::fprintf(stderr, "\n");
    std::fflush(stderr);

    QFile file(ArgonPaths::runtimeLogFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        return;

    QTextStream out(&file);
    out << QDateTime::currentDateTime().toString(Qt::ISODateWithMs)
        << " [" << level << "] "
        << message;
    if (context.file)
        out << " (" << context.file << ":" << context.line << ")";
    out << Qt::endl;
}
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
    QCoreApplication::setApplicationName("Argon");
    QCoreApplication::setOrganizationName("Argon");
    QCoreApplication::setApplicationVersion(QString::fromLatin1(ARGON_VERSION_STRING));

    QString pathsError;
    const bool pathsReady = ArgonPaths::ensureDirectoryStructure(&pathsError);
    qInstallMessageHandler(writeRuntimeLog);
    qInfo().noquote() << "[Paths] Runtime root:" << ArgonPaths::rootDirectory();
    qInfo().noquote() << "[Paths] User data root:" << ArgonPaths::userDataDirectory();
    qInfo().noquote() << "[Paths] Daily analytics root:" << ArgonPaths::analyticsDirectory();
    if (!pathsReady) {
        qCritical().noquote() << "[Paths] Startup stopped to protect user data:" << pathsError;
        return 1;
    }

    AppServices appServices;
    UserSettingsService userSettingsService;
    DailyAnalyticsService dailyAnalyticsService;
    DocumentService documentService;
    SearchService searchService;
    ReleaseMetadataService releaseMetadataService;
    UpdaterStatusService updaterStatusService;
    AppUpdateService appUpdateService;

    QObject::connect(
        &releaseMetadataService,
        &ReleaseMetadataService::stateChanged,
        &app,
        [&releaseMetadataService]() {
            if (!releaseMetadataService.checking())
                qInfo().noquote() << "[Versioning]" << releaseMetadataService.status();
        });

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("appServices", &appServices);
    engine.rootContext()->setContextProperty("appSettingsService", &userSettingsService);
    engine.rootContext()->setContextProperty("dailyAnalyticsService", &dailyAnalyticsService);
    engine.rootContext()->setContextProperty("documentService", &documentService);
    engine.rootContext()->setContextProperty("searchService", &searchService);
    engine.rootContext()->setContextProperty("releaseMetadataService", &releaseMetadataService);
    engine.rootContext()->setContextProperty("updaterStatusService", &updaterStatusService);
    engine.rootContext()->setContextProperty("appUpdateService", &appUpdateService);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(EXIT_FAILURE); },
        Qt::QueuedConnection);

    QString updateReadyFile;
    const QStringList arguments = QCoreApplication::arguments();
    for (qsizetype i = 1; i + 1 < arguments.size(); ++i) {
        if (arguments.at(i) == QStringLiteral("--argon-update-ready-file")) {
            updateReadyFile = arguments.at(i + 1);
            break;
        }
    }

    // The updater passes a one-time marker path only for an installation
    // attempt. A successful handshake requires a created QML root and an
    // atomically written, complete marker file.
    bool updateReadySignalScheduled = false;
    if (!updateReadyFile.isEmpty())
        qInfo().noquote() << "Update-ready handshake requested at" << updateReadyFile;

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [&app, updateReadyFile, &updateReadySignalScheduled](QObject *object,
                                                             const QUrl &) {
            if (!object || updateReadyFile.isEmpty()
                || updateReadySignalScheduled) {
                return;
            }
            updateReadySignalScheduled = true;
            QTimer::singleShot(0, &app, [&app, updateReadyFile]() {
                QSaveFile readyFile(updateReadyFile);
                const QByteArray markerContents = QByteArrayLiteral("ready\n");
                if (!readyFile.open(QIODevice::WriteOnly)
                    || readyFile.write(markerContents) != markerContents.size()
                    || !readyFile.commit()) {
                    qCritical().noquote() << "Could not write updater-ready marker:"
                                          << updateReadyFile;
                    app.exit(EXIT_FAILURE);
                    return;
                }
                qInfo() << "Updater-ready marker written after QML root creation.";
            });
        });

    engine.loadFromModule("Argon", "Main");
    // Bootstrap is launched as a background companion. It owns the updater version
    // comparison and writes a status JSON that the Argon menu reads.
    QTimer *updaterStatusRetryTimer = new QTimer(&app);
    updaterStatusRetryTimer->setInterval(300000);
    QObject::connect(
        updaterStatusRetryTimer,
        &QTimer::timeout,
        &updaterStatusService,
        &UpdaterStatusService::checkForUpdates);
    updaterStatusRetryTimer->start();
    QTimer::singleShot(0, &updaterStatusService, &UpdaterStatusService::checkForUpdates);

    // Check the Argon application release metadata immediately and retry periodically.
    QTimer *releaseMetadataRetryTimer = new QTimer(&app);
    releaseMetadataRetryTimer->setTimerType(Qt::PreciseTimer);
    releaseMetadataRetryTimer->setInterval(10000);
    QObject::connect(
        releaseMetadataRetryTimer,
        &QTimer::timeout,
        &releaseMetadataService,
        &ReleaseMetadataService::checkForUpdates);
    releaseMetadataRetryTimer->start();

    QTimer::singleShot(0, &releaseMetadataService, &ReleaseMetadataService::checkForUpdates);

    return app.exec();
}
