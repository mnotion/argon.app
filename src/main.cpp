#include <QGuiApplication>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QCoreApplication>
#include <QFile>
#include <QDateTime>
#include <QMutex>
#include <QMutexLocker>
#include <QTextStream>
#include <QTimer>
#include <cstdio>

#include "app/AppPaths.h"
#include "app/AppServices.h"
#include "analytics/DailyAnalyticsService.h"
#include "documents/DocumentService.h"
#include "search/SearchService.h"
#include "versioning/ReleaseMetadataService.h"

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
    if (!pathsReady)
        qWarning().noquote() << pathsError;

    AppServices appServices;
    DailyAnalyticsService dailyAnalyticsService;
    DocumentService documentService;
    SearchService searchService;
    ReleaseMetadataService releaseMetadataService;

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
    engine.rootContext()->setContextProperty("dailyAnalyticsService", &dailyAnalyticsService);
    engine.rootContext()->setContextProperty("documentService", &documentService);
    engine.rootContext()->setContextProperty("searchService", &searchService);
    engine.rootContext()->setContextProperty("releaseMetadataService", &releaseMetadataService);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(EXIT_FAILURE); },
        Qt::QueuedConnection);

    engine.loadFromModule("Argon", "Main");

    // This is an asynchronous metadata check only; it never downloads or installs a package.
    QTimer::singleShot(0, &releaseMetadataService, &ReleaseMetadataService::checkForUpdates);

    return app.exec();
}
