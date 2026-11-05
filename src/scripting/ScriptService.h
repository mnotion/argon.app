#pragma once

#include "Interpreter.h"

#include <QObject>
#include <QString>
#include <QVariantMap>

class AppServices;
class SearchService;

class ScriptService final : public QObject
{
    Q_OBJECT

public:
    ScriptService(SearchService &searchService, const AppServices &appServices,
                  QObject *parent = nullptr);

    Q_INVOKABLE QVariantMap execute(const QString &source);
    Q_INVOKABLE void reset();

private:
    SearchService &m_searchService;
    const AppServices &m_appServices;
    Argon::Scripting::Interpreter m_interpreter;
};
