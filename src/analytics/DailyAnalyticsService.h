#pragma once

#include <QObject>
#include <QString>
#include <QtGlobal>
#include <QJsonObject>
#include <QVariantList>

class QDate;

class DailyAnalyticsService final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(qint64 focusedSecondsToday READ focusedSecondsToday NOTIFY dailyStatsChanged)
    Q_PROPERTY(int completedFocusSessionsToday READ completedFocusSessionsToday NOTIFY dailyStatsChanged)
    Q_PROPERTY(QString dailyFilePath READ dailyFilePath NOTIFY dailyStatsChanged)

public:
    explicit DailyAnalyticsService(QObject *parent = nullptr);

    qint64 focusedSecondsToday() const;
    int completedFocusSessionsToday() const;
    QString dailyFilePath() const;

    Q_INVOKABLE void addFocusedSeconds(qint64 seconds);
    Q_INVOKABLE void addSubjectFocusedSeconds(qint64 seconds,
                                              const QString &subjectId,
                                              const QString &subjectName,
                                              const QString &subjectColour);
    Q_INVOKABLE void recordFocusSessionCompleted();
    Q_INVOKABLE void refreshToday();
    Q_INVOKABLE qint64 focusedSecondsForDate(const QString &isoDate) const;
    Q_INVOKABLE QVariantList subjectFocusForDate(const QString &isoDate) const;

signals:
    void dailyStatsChanged();

private:
    bool loadToday();
    bool saveToday() const;
    QString filePathForDate(const QDate &date) const;

    QString m_storageDirectory;
    QString m_loadedDate;
    qint64 m_focusedSecondsToday = 0;
    int m_completedFocusSessionsToday = 0;
    QJsonObject m_subjectFocusToday;
};
