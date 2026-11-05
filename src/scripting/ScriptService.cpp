#include "ScriptService.h"

#include "Interpreter.h"
#include "app/AppServices.h"
#include "search/SearchService.h"

#include <QJsonDocument>
#include <QVariantList>
#include <QVariantMap>

#include <stdexcept>
#include <string>
#include <utility>

ScriptService::ScriptService(SearchService &searchService,
                             const AppServices &appServices,
                             QObject *parent)
    : QObject(parent),
      m_searchService(searchService),
      m_appServices(appServices)
{
    using Argon::Scripting::Value;

    (void)m_interpreter.registerNativeFunction(
        "applicationVersion",
        [this](const std::vector<Value> &arguments, std::vector<std::string> &) {
            if (!arguments.empty())
                throw std::runtime_error("applicationVersion() takes no arguments.");
            return Value(m_appServices.version().toStdString());
        });

    (void)m_interpreter.registerNativeFunction(
        "search",
        [this](const std::vector<Value> &arguments, std::vector<std::string> &) {
            if (arguments.size() != 1 || !arguments[0].isString())
                throw std::runtime_error("search() expects one string query.");

            const QVariantMap response =
                m_searchService.startNameSearch(QString::fromStdString(arguments[0].asString()));
            const QByteArray json =
                QJsonDocument::fromVariant(response).toJson(QJsonDocument::Compact);
            return Value(std::string(json.constData(), static_cast<std::size_t>(json.size())));
        });

    (void)m_interpreter.registerNativeFunction(
        "nextSearchPage",
        [this](const std::vector<Value> &arguments, std::vector<std::string> &) {
            if (!arguments.empty())
                throw std::runtime_error("nextSearchPage() takes no arguments.");

            const QVariantMap response = m_searchService.nextNameSearchPage();
            const QByteArray json =
                QJsonDocument::fromVariant(response).toJson(QJsonDocument::Compact);
            return Value(std::string(json.constData(), static_cast<std::size_t>(json.size())));
        });
}

QVariantMap ScriptService::execute(const QString &source)
{
    const auto result = m_interpreter.execute(source.toStdString());

    QVariantList output;
    output.reserve(static_cast<qsizetype>(result.output.size()));
    for (const std::string &line : result.output)
        output.append(QString::fromStdString(line));

    QVariantList diagnostics;
    diagnostics.reserve(static_cast<qsizetype>(result.diagnostics.size()));
    for (const auto &diagnostic : result.diagnostics) {
        QVariantMap item;
        item.insert(QStringLiteral("line"), static_cast<qulonglong>(diagnostic.line));
        item.insert(QStringLiteral("column"), static_cast<qulonglong>(diagnostic.column));
        item.insert(QStringLiteral("message"), QString::fromStdString(diagnostic.message));
        diagnostics.append(item);
    }

    QVariantMap response;
    response.insert(QStringLiteral("success"), result.success);
    response.insert(QStringLiteral("output"), output);
    response.insert(QStringLiteral("diagnostics"), diagnostics);
    if (result.lastValue.has_value())
        response.insert(QStringLiteral("lastValue"),
                        QString::fromStdString(result.lastValue->toString()));
    return response;
}

void ScriptService::reset()
{
    m_interpreter = Argon::Scripting::Interpreter{};
}
