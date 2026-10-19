#include <QCoreApplication>
#include <QDate>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>
#include <QTemporaryDir>

#include <iostream>

#include "AppPaths.h"
#include "UserSettingsService.h"

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

bool writeJsonFile(const QString &path, const QJsonObject &object)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    const QByteArray bytes = QJsonDocument(object).toJson(QJsonDocument::Indented);
    return file.write(bytes) == bytes.size();
}

QJsonObject readJsonFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object() : QJsonObject();
}
}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    int failures = 0;
    QTemporaryDir temporaryRoot;
    check(temporaryRoot.isValid(), "Create isolated settings root", failures);
    if (!temporaryRoot.isValid())
        return 1;

    qputenv("ARGON_DATA_ROOT", temporaryRoot.path().toUtf8());
    const QString expectedSettingsPath = QDir(temporaryRoot.path()).filePath(
        QStringLiteral("UserData/Settings/app-settings.json"));

    {
        UserSettingsService settings;
        check(settings.value(QStringLiteral("missing.key"), false).toBool() == false,
              "Return caller-provided defaults for missing keys", failures);
        check(settings.setValue(QStringLiteral("preferences.timerSoundEnabled"), false),
              "Persist a boolean preference", failures);
        check(settings.setValue(QStringLiteral("ui.activePage"), QStringLiteral("Timer")),
              "Persist the active page", failures);
        check(settings.setValue(QStringLiteral("timer.elapsedMilliseconds"), 372000.0),
              "Persist accumulated stopwatch time", failures);
        check(settings.setValue(QStringLiteral("timer.wasRunning"), true),
              "Persist whether the stopwatch was running", failures);
    }

    check(QFileInfo::exists(expectedSettingsPath),
          "Store preferences under UserData/Settings outside App", failures);
    check(!QFileInfo::exists(QDir(temporaryRoot.path()).filePath(
              QStringLiteral("App/app-settings.json"))),
          "Never write application preferences into the replaceable App directory", failures);

    {
        UserSettingsService settings;
        check(!settings.value(QStringLiteral("preferences.timerSoundEnabled"), true).toBool(),
              "Restore a saved boolean preference", failures);
        check(settings.value(QStringLiteral("ui.activePage"), QStringLiteral("Search")).toString()
                  == QStringLiteral("Timer"),
              "Restore the saved active page", failures);
        check(qAbs(settings.value(QStringLiteral("timer.elapsedMilliseconds"), 0.0).toDouble()
                   - 372000.0) < 0.001,
              "Restore accumulated stopwatch time", failures);
        check(settings.value(QStringLiteral("timer.wasRunning"), false).toBool(),
              "Restore the stopwatch running state", failures);
    }

    // A malformed settings file must be copied to a recovery file before it
    // can be replaced, so preferences cannot silently destroy the only copy.
    const QString recoveryRoot = QDir(temporaryRoot.path()).filePath(
        QStringLiteral("recovery-case"));
    qputenv("ARGON_DATA_ROOT", recoveryRoot.toUtf8());
    const QString recoveryDirectory = QDir(recoveryRoot).filePath(
        QStringLiteral("UserData/Settings"));
    check(QDir().mkpath(recoveryDirectory), "Create corruption-recovery settings directory", failures);
    const QString recoverySettingsPath = QDir(recoveryDirectory).filePath(
        QStringLiteral("app-settings.json"));
    const QByteArray malformedSettings("{invalid-json");
    {
        QFile file(recoverySettingsPath);
        const bool opened = file.open(QIODevice::WriteOnly);
        const bool written = opened && file.write(malformedSettings) == malformedSettings.size();
        file.close();
        check(written, "Create malformed settings fixture", failures);
    }
    {
        UserSettingsService settings;
        check(settings.setValue(QStringLiteral("preferences.lightMode"), true),
              "Resume settings writes after creating a recovery copy", failures);
    }
    const QStringList recoveryFiles = QDir(recoveryDirectory).entryList(
        {QStringLiteral("app-settings.json.corrupt-*")}, QDir::Files);
    check(!recoveryFiles.isEmpty(), "Preserve malformed settings in a recovery copy", failures);
    if (!recoveryFiles.isEmpty()) {
        QFile backup(QDir(recoveryDirectory).filePath(recoveryFiles.first()));
        const bool opened = backup.open(QIODevice::ReadOnly);
        check(opened && backup.readAll() == malformedSettings,
              "Recovery copy retains the original settings bytes", failures);
    }

    // Simulate an executable that accidentally saved data beneath
    // %LOCALAPPDATA%\\Argon instead of the canonical Argon-sim root.
    const QString migrationBase = QDir(temporaryRoot.path()).filePath(
        QStringLiteral("migration"));
    const QString simulatedLocalAppData = QDir(migrationBase).filePath(
        QStringLiteral("localappdata"));
    const QString canonicalRoot = QDir(simulatedLocalAppData).filePath(
        QStringLiteral("Argon-sim"));
    const QString legacyUserData = QDir(simulatedLocalAppData).filePath(
        QStringLiteral("Argon/UserData"));
    const QString canonicalUserData = QDir(canonicalRoot).filePath(
        QStringLiteral("UserData"));
    const QString staleLauncherRoot = QDir(migrationBase).filePath(
        QStringLiteral("desktop/Argon-sim"));
    const QString staleLauncherUserData = QDir(staleLauncherRoot).filePath(
        QStringLiteral("UserData"));
    qputenv("LOCALAPPDATA", simulatedLocalAppData.toUtf8());
#ifdef Q_OS_WIN
    // A newer process inherited the previous launcher's Desktop-root override.
    // It must redirect to LocalAppData/Argon-sim while migrating from that root.
    qputenv("ARGON_DATA_ROOT", staleLauncherRoot.toUtf8());
#else
    qputenv("ARGON_DATA_ROOT", canonicalRoot.toUtf8());
#endif

    QJsonObject legacyValues;
    legacyValues.insert(QStringLiteral("timer.elapsedMilliseconds"), 120000.0);
    legacyValues.insert(QStringLiteral("timer.wasRunning"), true);
    legacyValues.insert(QStringLiteral("preferences.lightMode"), false);
    QJsonObject canonicalValues;
    canonicalValues.insert(QStringLiteral("timer.elapsedMilliseconds"), 0.0);
    canonicalValues.insert(QStringLiteral("timer.wasRunning"), false);
    canonicalValues.insert(QStringLiteral("preferences.lightMode"), true);

    const QString legacySettingsPath = QDir(legacyUserData).filePath(
        QStringLiteral("Settings/app-settings.json"));
    const QString canonicalSettingsPath = QDir(canonicalUserData).filePath(
        QStringLiteral("Settings/app-settings.json"));
    check(writeJsonFile(legacySettingsPath, QJsonObject{
              {QStringLiteral("schemaVersion"), 1},
              {QStringLiteral("values"), legacyValues}}),
          "Create old-root settings containing two saved minutes", failures);
    check(writeJsonFile(canonicalSettingsPath, QJsonObject{
              {QStringLiteral("schemaVersion"), 1},
              {QStringLiteral("values"), canonicalValues}}),
          "Create canonical settings with stale zero timer state", failures);

    const QString today = QDate::currentDate().toString(Qt::ISODate);
    const QString dailyFileName = today + QStringLiteral(".json");
    const QString legacyDailyPath = QDir(legacyUserData).filePath(
        QStringLiteral("Analytics/Daily/") + dailyFileName);
    const QString canonicalDailyPath = QDir(canonicalUserData).filePath(
        QStringLiteral("Analytics/Daily/") + dailyFileName);
    check(writeJsonFile(legacyDailyPath, QJsonObject{
              {QStringLiteral("schemaVersion"), 1},
              {QStringLiteral("date"), today},
              {QStringLiteral("focusedSeconds"), 120},
              {QStringLiteral("completedFocusSessions"), 1},
              {QStringLiteral("updatedAt"), QStringLiteral("2026-10-18T10:00:00")}}),
          "Create the legacy daily-focus record", failures);
    check(writeJsonFile(canonicalDailyPath, QJsonObject{
              {QStringLiteral("schemaVersion"), 1},
              {QStringLiteral("date"), today},
              {QStringLiteral("focusedSeconds"), 0},
              {QStringLiteral("completedFocusSessions"), 0},
              {QStringLiteral("updatedAt"), QStringLiteral("2026-10-18T10:01:00")}}),
          "Create a canonical zero-minute daily record", failures);

#ifdef Q_OS_WIN
    const QString staleLauncherFilePath = QDir(staleLauncherUserData).filePath(
        QStringLiteral("Settings/launcher-origin.json"));
    check(writeJsonFile(staleLauncherFilePath,
          QJsonObject{{QStringLiteral("origin"), QStringLiteral("old Desktop root")}}),
          "Create a file under the stale launcher's user-data root", failures);
#endif

    const QString legacyNotePath = QDir(legacyUserData).filePath(
        QStringLiteral("Documents/legacy-note.txt"));
    check(QDir().mkpath(QFileInfo(legacyNotePath).absolutePath()),
          "Create legacy document directory", failures);
    QFile legacyNote(legacyNotePath);
    const bool noteOpened = legacyNote.open(QIODevice::WriteOnly | QIODevice::Text);
    const QByteArray noteContents("keep this user file");
    const bool noteWritten = noteOpened
        && legacyNote.write(noteContents) == noteContents.size();
    legacyNote.close();
    check(noteWritten, "Create legacy user document", failures);

    QString migrationError;
    check(ArgonPaths::ensureDirectoryStructure(&migrationError),
          "Prepare canonical root and migrate duplicate-root user data", failures);

#ifdef Q_OS_WIN
    check(ArgonPaths::rootDirectory() == canonicalRoot,
          "Redirect stale Desktop Argon-sim override to the canonical LocalAppData root", failures);
    check(QFileInfo::exists(QDir(canonicalUserData).filePath(
              QStringLiteral("Settings/launcher-origin.json"))),
          "Recover user files from the stale launcher's overridden root", failures);
#endif

    const QJsonObject migratedSettings = readJsonFile(canonicalSettingsPath);
    const QJsonObject migratedValues = migratedSettings.value(
        QStringLiteral("values")).toObject();
    check(qAbs(migratedValues.value(QStringLiteral("timer.elapsedMilliseconds")).toDouble()
               - 120000.0) < 0.001,
          "Merge the greater saved stopwatch duration instead of resetting to zero", failures);
    check(migratedValues.value(QStringLiteral("timer.wasRunning")).toBool(),
          "Restore the previous stopwatch running state when its elapsed time is newer", failures);
    check(migratedValues.value(QStringLiteral("preferences.lightMode")).toBool(),
          "Keep canonical preferences while recovering timer data", failures);

    const QJsonObject migratedDaily = readJsonFile(canonicalDailyPath);
    check(migratedDaily.value(QStringLiteral("focusedSeconds")).toInt() == 120,
          "Merge two minutes of daily focus time over a zero-minute record", failures);
    check(migratedDaily.value(QStringLiteral("completedFocusSessions")).toInt() == 1,
          "Preserve completed daily focus sessions", failures);
    check(QFileInfo::exists(QDir(canonicalUserData).filePath(
              QStringLiteral("Documents/legacy-note.txt"))),
          "Copy other missing user files into the canonical UserData tree", failures);
    check(QFileInfo::exists(legacySettingsPath) && QFileInfo::exists(legacyDailyPath)
              && QFileInfo::exists(legacyNotePath),
          "Keep all source files intact after migration", failures);

    {
        UserSettingsService migratedSettingsService;
        check(qAbs(migratedSettingsService.value(
                       QStringLiteral("timer.elapsedMilliseconds"), 0.0).toDouble()
                   - 120000.0) < 0.001,
              "The new settings service reads the recovered stopwatch minutes", failures);
    }

#ifdef Q_OS_WIN
    qunsetenv("ARGON_DATA_ROOT");
    check(ArgonPaths::rootDirectory() == canonicalRoot,
          "Normal Windows launches resolve to LocalAppData/Argon-sim, never LocalAppData/Argon",
          failures);
#endif

    if (failures != 0) {
        std::cerr << failures << " user-settings test(s) failed.\n";
        return 1;
    }

    std::cout << "All user-settings tests passed.\n";
    return 0;
}
