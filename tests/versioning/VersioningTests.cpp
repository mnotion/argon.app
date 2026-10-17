#include <QCoreApplication>
#include <QByteArray>

#include <iostream>
#include <limits>

#include "LatestReleaseMetadata.h"
#include "VersionNumber.h"

namespace {
void check(bool condition, const char *description, int &failures)
{
    if (condition) {
        std::cout << "[PASS] " << description << '\n';
    } else {
        std::cerr << "[FAIL] " << description << '\n';
        ++failures;
    }
}
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    int failures = 0;

    const auto v100 = VersionNumber::parse(QStringLiteral("1.0.0"));
    const auto v110 = VersionNumber::parse(QStringLiteral("1.1.0"));
    const auto v190 = VersionNumber::parse(QStringLiteral("1.9.0"));
    const auto v1100 = VersionNumber::parse(QStringLiteral("1.10.0"));
    const auto v19999 = VersionNumber::parse(QStringLiteral("1.99.99"));
    const auto v200 = VersionNumber::parse(QStringLiteral("2.0.0"));

    check(v100.has_value(), "Accept version 1.0.0", failures);
    check(v110.has_value(), "Accept version 1.1.0", failures);
    check(v100 && v110 && *v100 < *v110, "1.0.0 is older than 1.1.0", failures);
    check(v190 && v1100 && *v190 < *v1100, "Compare components numerically: 1.9.0 < 1.10.0", failures);
    check(v19999 && v200 && *v19999 < *v200, "Major component takes precedence", failures);
    check(v1100 && v190 && v1100->isNewerThan(*v190), "isNewerThan uses numeric ordering", failures);

    const auto sameVersion = VersionNumber::parse(QStringLiteral("1.10.0"));
    check(v1100 && sameVersion && *v1100 == *sameVersion, "Equal versions compare equal", failures);
    check(v1100 && v190 && !v190->isNewerThan(*v1100), "Older version is not newer", failures);

    const QStringList invalidVersions = {
        QString(),
        QStringLiteral("1"),
        QStringLiteral("1.2"),
        QStringLiteral("1.2.3.4"),
        QStringLiteral("1.2.x"),
        QStringLiteral("01.2.3"),
        QStringLiteral("1.02.3"),
        QStringLiteral("1.2.03"),
        QStringLiteral("-1.2.3"),
        QStringLiteral(" 1.2.3"),
        QStringLiteral("1.2.3 "),
        QStringLiteral("18446744073709551616.0.0")
    };
    bool everyInvalidRejected = true;
    for (const QString &candidate : invalidVersions) {
        if (VersionNumber::parse(candidate)) {
            everyInvalidRejected = false;
            std::cerr << "[DETAIL] Unexpectedly accepted: "
                      << candidate.toStdString() << '\n';
        }
    }
    check(everyInvalidRejected, "Reject malformed versions and numeric overflow", failures);

    const QByteArray validMetadata = R"json(
{
  "schemaVersion": 1,
  "product": "Argon",
  "channel": "stable",
  "version": "1.10.0",
  "releaseNotesUrl": "https://github.com/ananas123123/argon.app/releases"
}
)json";
    QString metadataError;
    const auto metadata = LatestReleaseMetadata::parse(validMetadata, &metadataError);
    check(metadata.has_value(), "Parse valid latest.json metadata", failures);
    check(metadata && metadata->version.toString() == QStringLiteral("1.10.0"),
          "Metadata preserves the parsed numeric version", failures);
    check(metadata && metadata->releaseNotesUrl.scheme() == QStringLiteral("https"),
          "Metadata accepts HTTPS release notes", failures);

    const QByteArray invalidVersionMetadata = R"json(
{
  "schemaVersion": 1,
  "product": "Argon",
  "channel": "stable",
  "version": "1.10",
  "releaseNotesUrl": "https://github.com/ananas123123/argon.app/releases"
}
)json";
    check(!LatestReleaseMetadata::parse(invalidVersionMetadata),
          "Reject metadata containing a non-three-part version", failures);

    const QByteArray invalidChannelMetadata = R"json(
{
  "schemaVersion": 1,
  "product": "Argon",
  "channel": "beta",
  "version": "1.0.0",
  "releaseNotesUrl": "https://github.com/ananas123123/argon.app/releases"
}
)json";
    check(!LatestReleaseMetadata::parse(invalidChannelMetadata),
          "Reject unsupported release channels", failures);

    const QByteArray invalidUrlMetadata = R"json(
{
  "schemaVersion": 1,
  "product": "Argon",
  "channel": "stable",
  "version": "1.0.0",
  "releaseNotesUrl": "http://example.com/releases"
}
)json";
    check(!LatestReleaseMetadata::parse(invalidUrlMetadata),
          "Reject non-HTTPS release notes URLs", failures);

    if (failures != 0) {
        std::cerr << failures << " versioning test(s) failed.\n";
        return 1;
    }

    std::cout << "All versioning tests passed.\n";
    return 0;
}
