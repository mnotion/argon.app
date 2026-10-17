#pragma once

#include <optional>

#include <QByteArray>
#include <QString>
#include <QUrl>

#include "VersionNumber.h"

struct LatestReleaseMetadata final
{
    VersionNumber version;
    QString channel;
    QUrl releaseNotesUrl;

    // Parses and validates the JSON contract used by latest.json.
    // This validates structure and fields, not publisher authenticity.
    static std::optional<LatestReleaseMetadata> parse(
        const QByteArray &json,
        QString *errorMessage = nullptr);
};
