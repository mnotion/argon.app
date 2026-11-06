#pragma once

#include <QString>

namespace ArgonPaths
{
QString rootDirectory();
QString appDirectory();
QString updaterDirectory();
QString bootstrapDirectory();

QString userDataDirectory();
QString settingsDirectory();
QString cacheDirectory();
QString searchRootDirectory();
QString documentsDirectory();
QString analyticsDirectory();

QString updatesDirectory();
QString downloadsDirectory();
QString stagingDirectory();
QString backupsDirectory();

QString logsDirectory();
QString runtimeLogFilePath();

// Creates the complete per-user directory layout. Returns false if any required
// directory could not be created; details are written to errorMessage when provided.
bool ensureDirectoryStructure(QString *errorMessage = nullptr);
} // namespace ArgonPaths
