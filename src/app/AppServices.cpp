#include "AppServices.h"

#include <QCoreApplication>

AppServices::AppServices(QObject *parent) : QObject(parent) {}

QString AppServices::applicationName() const
{
    return QCoreApplication::applicationName();
}

QString AppServices::version() const
{
    return QCoreApplication::applicationVersion();
}
