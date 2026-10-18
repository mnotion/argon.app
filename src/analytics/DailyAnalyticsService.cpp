#include "DailyAnalyticsService.h"
#include "../app/AppPaths.h"

#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QCoreApplication>
#include <QDebug>

namespace
{
bool migrateLegacyAnalyticsData()
{
    const QString markerPath = QDir(ArgonPaths::userDataDirectory())
        .filePath(QStringLiteral(".legacy-analytics-migration-v1"));
    if (QFileInfo::exists(markerPath))
        return true;

    QString legacyDirectory;
    const QString genericData = QStandardPaths::writableLocation(
        QStandardPaths::GenericDataLocation);
    if (!genericData.isEmpty()) {
        legacyDirectory = QDir(genericData).filePath(
            QStringLiteral("Argon/user-data/analytics/daily"));
    }
    if (legacyDirectory.isEmpty() || !QDir(legacyDirectory).exists()) {
        legacyDirectory = QDir(QCoreApplication::applicationDirPath()).filePath(
            QStringLiteral("Argon/user-data/analytics/daily"));
    }

    if (!QDir(legacyDirectory).exists()
        || QDir::cleanPath(legacyDirectory).compare(
               QDir::cleanPath(ArgonPaths::analyticsDirectory()),
#ifdef Q_OS_WIN
               Qt::CaseInsensitive
#else
               Qt::CaseSensitive
#endif
           ) == 0) {
        return true;
    }

    const QFileInfoList legacyFiles = QDir(legacyDirectory).entryInfoList(
        QStringList{QStringLiteral("*.json")},
        QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
        QDir::Name);

    for (const QFileInfo &legacyFile : legacyFiles) {
        if (legacyFile.isSymLink())
            continue;

        const QString destination = QDir(ArgonPaths::analyticsDirectory())
            .filePath(legacyFile.fileName());
        if (QFileInfo::exists(destination))
            continue;
        if (!QFile::copy(legacyFile.absoluteFilePath(), destination)) {
            qWarning().noquote() << "Could not migrate legacy Argon analytics file:"
                                 << legacyFile.absoluteFilePath()
                                 << "(the original file remains in place).";
            return false;
        }
    }

    QSaveFile marker(markerPath);
    const QByteArray markerContents("completed");
    if (!marker.open(QIODevice::WriteOnly | QIODevice::Text)
        || marker.write(markerContents) != markerContents.size()
        || !marker.commit()) {
        qWarning().noquote() << "Could not write Argon analytics migration marker:" << markerPath;
        return false;
    }

    if (!legacyFiles.isEmpty())
        qInfo() << "Migrated legacy Argon analytics into" << ArgonPaths::analyticsDirectory();
    return true;
}
}

DailyAnalyticsService::DailyAnalyticsService(QObject *parent)
    : QObject(parent)
{
    m_storageDirectory = ArgonPaths::analyticsDirectory();
    migrateLegacyAnalyticsData();

    if (!QDir().mkpath(m_storageDirectory))
        qWarning() << "Could not create Argon daily analytics directory:" << m_storageDirectory;

    loadToday();
}

qint64 DailyAnalyticsService::focusedSecondsToday() const
{
    return m_focusedSecondsToday;
}

int DailyAnalyticsService::completedFocusSessionsToday() const
{
    return m_completedFocusSessionsToday;
}

QString DailyAnalyticsService::dailyFilePath() const
{
    return filePathForDate(QDate::currentDate());
}

void DailyAnalyticsService::addFocusedSeconds(qint64 seconds)
{
    if (seconds <= 0)
        return;

    if (!loadToday()) {
        qWarning() << "Could not load today's Argon analytics data.";
        return;
    }

    m_focusedSecondsToday += seconds;
    if (!saveToday())
        qWarning() << "Could not save today's Argon focus-time counter.";
    emit dailyStatsChanged();
}

void DailyAnalyticsService::recordFocusSessionCompleted()
{
    if (!loadToday()) {
        qWarning() << "Could not load today's Argon analytics data.";
        return;
    }

    ++m_completedFocusSessionsToday;
    if (!saveToday())
        qWarning() << "Could not save today's completed-session counter.";
    emit dailyStatsChanged();
}

void DailyAnalyticsService::refreshToday()
{
    const QString previousDate = m_loadedDate;
    if (!loadToday()) {
        qWarning() << "Could not refresh today's Argon analytics data.";
        return;
    }

    if (previousDate != m_loadedDate)
        emit dailyStatsChanged();
}


qint64 DailyAnalyticsService::focusedSecondsForDate(const QString &isoDate) const
{
    const QDate date = QDate::fromString(isoDate, Qt::ISODate);
    if (!date.isValid() || date.toString(Qt::ISODate) != isoDate)
        return 0;

    QFile file(filePathForDate(date));
    if (!file.exists() || !file.open(QIODevice::ReadOnly))
        return 0;

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return 0;

    const QJsonObject object = document.object();
    if (object.value(QStringLiteral("date")).toString() != isoDate)
        return 0;

    const double seconds = object.value(QStringLiteral("focusedSeconds")).toDouble(0);
    return qMax<qint64>(0, qint64(seconds));
}

bool DailyAnalyticsService::loadToday()
{
    const QString today = QDate::currentDate().toString(Qt::ISODate);
    if (m_loadedDate == today)
        return true;

    m_loadedDate = today;
    m_focusedSecondsToday = 0;
    m_completedFocusSessionsToday = 0;

    const QString path = filePathForDate(QDate::currentDate());
    QFile file(path);
    if (!file.exists())
        return saveToday();

    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "Could not read Argon daily analytics file:" << path << file.errorString();
        return false;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        qWarning() << "Invalid Argon daily analytics JSON:" << path << parseError.errorString();
        return false;
    }

    const QJsonObject object = document.object();
    if (object.value(QStringLiteral("date")).toString() != today) {
        qWarning() << "Date mismatch in Argon daily analytics file:" << path;
        return false;
    }

    m_focusedSecondsToday = qMax<qint64>(0, qint64(object.value(QStringLiteral("focusedSeconds")).toDouble(0)));
    m_completedFocusSessionsToday = qMax(0, object.value(QStringLiteral("completedFocusSessions")).toInt(0));
    return true;
}

bool DailyAnalyticsService::saveToday() const
{
    QSaveFile file(filePathForDate(QDate::currentDate()));
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "Could not write Argon daily analytics file:" << file.fileName() << file.errorString();
        return false;
    }

    QJsonObject object;
    object.insert(QStringLiteral("schemaVersion"), 1);
    object.insert(QStringLiteral("date"), QDate::currentDate().toString(Qt::ISODate));
    object.insert(QStringLiteral("focusedSeconds"), double(m_focusedSecondsToday));
    object.insert(QStringLiteral("completedFocusSessions"), m_completedFocusSessionsToday);
    object.insert(QStringLiteral("updatedAt"), QDateTime::currentDateTime().toString(Qt::ISODateWithMs));

    const QByteArray json = QJsonDocument(object).toJson(QJsonDocument::Indented);
    if (file.write(json) != json.size()) {
        qWarning() << "Could not write complete Argon daily analytics file:" << file.fileName() << file.errorString();
        return false;
    }
    if (!file.commit()) {
        qWarning() << "Could not commit Argon daily analytics file:" << file.fileName() << file.errorString();
        return false;
    }
    return true;
}

QString DailyAnalyticsService::filePathForDate(const QDate &date) const
{
    return QDir(m_storageDirectory).filePath(date.toString(Qt::ISODate) + QStringLiteral(".json"));
}
