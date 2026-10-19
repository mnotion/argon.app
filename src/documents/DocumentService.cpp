#include "DocumentService.h"

DocumentService::DocumentService(QObject *parent) : QObject(parent) {}
QStringList DocumentService::recentDocuments() const { return m_recentDocuments; }
