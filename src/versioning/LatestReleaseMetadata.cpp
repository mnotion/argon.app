#include "LatestReleaseMetadata.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>

namespace {
void assignError(QString *target, const QString &message)
{
    if (target)
        *target = message;
}
}

std::optional<LatestReleaseMetadata> LatestReleaseMetadata::parse(
    const QByteArray &json,
    QString *errorMessage)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(json, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        assignError(
            errorMessage,
            QStringLiteral("Release metadata is not a valid JSON object: %1")
                .arg(parseError.errorString()));
        return std::nullopt;
    }

    const QJsonObject object = document.object();
    if (!object.value(QStringLiteral("schemaVersion")).isDouble()
        || object.value(QStringLiteral("schemaVersion")).toInt(-1) != 1) {
        assignError(errorMessage, QStringLiteral("Unsupported release metadata schemaVersion."));
        return std::nullopt;
    }

    if (object.value(QStringLiteral("product")).toString() != QStringLiteral("Argon")) {
        assignError(errorMessage, QStringLiteral("Release metadata product is not Argon."));
        return std::nullopt;
    }

    const QString channel = object.value(QStringLiteral("channel")).toString();
    if (channel != QStringLiteral("stable")) {
        assignError(errorMessage, QStringLiteral("Only the stable release channel is supported."));
        return std::nullopt;
    }

    const QJsonValue versionValue = object.value(QStringLiteral("version"));
    if (!versionValue.isString()) {
        assignError(errorMessage, QStringLiteral("Release metadata version must be a string."));
        return std::nullopt;
    }

    QString versionError;
    const auto version = VersionNumber::parse(versionValue.toString(), &versionError);
    if (!version) {
        assignError(
            errorMessage,
            QStringLiteral("Release metadata contains an invalid version: %1").arg(versionError));
        return std::nullopt;
    }

    const QJsonValue releaseNotesValue = object.value(QStringLiteral("releaseNotesUrl"));
    if (!releaseNotesValue.isString() || releaseNotesValue.toString().trimmed().isEmpty()) {
        assignError(errorMessage, QStringLiteral("Release metadata releaseNotesUrl is required."));
        return std::nullopt;
    }

    const QUrl releaseNotesUrl(releaseNotesValue.toString(), QUrl::StrictMode);
    if (!releaseNotesUrl.isValid()
        || releaseNotesUrl.scheme() != QStringLiteral("https")
        || releaseNotesUrl.host().isEmpty()
        || !releaseNotesUrl.userName().isEmpty()
        || !releaseNotesUrl.password().isEmpty()) {
        assignError(errorMessage, QStringLiteral("releaseNotesUrl must be a valid HTTPS URL."));
        return std::nullopt;
    }

    assignError(errorMessage, QString());
    return LatestReleaseMetadata{*version, channel, releaseNotesUrl};
}
