#pragma once
#include <QObject>
#include <QString>

class AppServices final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString applicationName READ applicationName CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)
public:
    explicit AppServices(QObject *parent = nullptr);
    QString applicationName() const;
    QString version() const;
};
