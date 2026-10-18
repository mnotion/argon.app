#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <winhttp.h>
#include <bcrypt.h>
#include <commctrl.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cwchar>
#include <filesystem>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <vector>

#ifndef ARGON_APP_DIRECTORY_URL
#define ARGON_APP_DIRECTORY_URL "https://raw.githubusercontent.com/mnotion/argon.updater/updater-intermediate/directory.json"
#endif

namespace fs = std::filesystem;

namespace {
constexpr unsigned long long kMaximumMetadataBytes = 1024ULL * 1024ULL;
constexpr unsigned long long kMaximumExecutableBytes = 512ULL * 1024ULL * 1024ULL;

struct Paths {
    fs::path root;
    fs::path updates;
    fs::path downloads;
    fs::path staging;
    fs::path backups;
    fs::path appDirectory;
    fs::path userData;
    fs::path logs;
};

struct AppRelease {
    std::string version;
    std::string packageUrl;
    std::string sha256;
    unsigned long long sizeBytes = 0;
};

bool g_silentUiMode = false;
bool g_downloadOnlyMode = false;
bool g_installOnlyMode = false;
fs::path g_statusFile;
std::string g_expectedVersion;

std::wstring widenUtf8(const std::string &value)
{
    if (value.empty())
        return {};
    const int needed = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                            value.data(), static_cast<int>(value.size()),
                                            nullptr, 0);
    if (needed <= 0)
        return L"";
    std::wstring output(static_cast<size_t>(needed), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                        value.data(), static_cast<int>(value.size()),
                        output.data(), needed);
    return output;
}

std::string narrowUtf8(const std::wstring &value)
{
    if (value.empty())
        return {};
    const int needed = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (needed <= 0)
        return {};
    std::string output(static_cast<size_t>(needed), '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), output.data(), needed, nullptr, nullptr);
    return output;
}

std::string jsonEscape(const std::string &value)
{
    std::string escaped;
    escaped.reserve(value.size() + 8);
    for (const unsigned char ch : value) {
        switch (ch) {
        case '"': escaped += "\\\""; break;
        case '\\': escaped += "\\\\"; break;
        case '\b': escaped += "\\b"; break;
        case '\f': escaped += "\\f"; break;
        case '\n': escaped += "\\n"; break;
        case '\r': escaped += "\\r"; break;
        case '\t': escaped += "\\t"; break;
        default:
            if (ch < 0x20) {
                static constexpr char hex[] = "0123456789abcdef";
                escaped += "\\u00";
                escaped += hex[(ch >> 4) & 0x0f];
                escaped += hex[ch & 0x0f];
            } else {
                escaped.push_back(static_cast<char>(ch));
            }
        }
    }
    return escaped;
}

void writeUiStatus(const char *state, const std::wstring &status, int progress,
                   const std::string &version, const fs::path &downloadedPath,
                   const std::wstring &error)
{
    if (g_statusFile.empty())
        return;
    std::error_code ec;
    fs::create_directories(g_statusFile.parent_path(), ec);
    if (ec)
        return;

    const std::string body =
        "{\"state\":\"" + std::string(state)
        + "\",\"status\":\"" + jsonEscape(narrowUtf8(status))
        + "\",\"progress\":" + std::to_string(std::max(0, std::min(progress, 100)))
        + ",\"version\":\"" + jsonEscape(version)
        + "\",\"downloadedPath\":\"" + jsonEscape(narrowUtf8(downloadedPath.wstring()))
        + "\",\"error\":\"" + jsonEscape(narrowUtf8(error)) + "\"}\n";

    fs::path temporary = g_statusFile;
    temporary += L".tmp";
    HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return;
    size_t offset = 0;
    bool okay = true;
    while (offset < body.size()) {
        const DWORD request = static_cast<DWORD>(
            std::min<size_t>(body.size() - offset, 64 * 1024));
        DWORD written = 0;
        if (!WriteFile(file, body.data() + offset, request, &written, nullptr)
            || written != request) {
            okay = false;
            break;
        }
        offset += written;
    }
    if (okay)
        okay = FlushFileBuffers(file) != FALSE;
    CloseHandle(file);
    if (okay)
        MoveFileExW(temporary.c_str(), g_statusFile.c_str(),
                    MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
    else
        DeleteFileW(temporary.c_str());
}

std::wstring windowsError(const std::wstring &operation, DWORD code = GetLastError())
{
    wchar_t *buffer = nullptr;
    const DWORD count = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
            | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<wchar_t *>(&buffer), 0, nullptr);

    std::wstring detail = count && buffer
        ? std::wstring(buffer, count)
        : L"Windows error " + std::to_wstring(code);
    if (buffer)
        LocalFree(buffer);
    while (!detail.empty() && (detail.back() == L'\r' || detail.back() == L'\n'
                               || detail.back() == L' ')) {
        detail.pop_back();
    }
    return operation + L": " + detail;
}

std::optional<Paths> resolvePaths(std::wstring &error)
{
    std::vector<wchar_t> buffer(32768, L'\0');
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                             static_cast<DWORD>(buffer.size()));
    if (length == 0 || length >= buffer.size()) {
        error = windowsError(L"Could not locate ArgonUpdater.exe");
        return std::nullopt;
    }

    const fs::path executable(std::wstring(buffer.data(), length));
    const fs::path updaterDirectory = executable.parent_path();
    Paths paths;
    paths.root = updaterDirectory.parent_path();
    if (paths.root.empty() || paths.root == updaterDirectory) {
        error = L"ArgonUpdater.exe must be inside the Argon-sim\\Updater directory.";
        return std::nullopt;
    }
    paths.updates = paths.root / L"Updates";
    paths.downloads = paths.updates / L"Downloads";
    paths.staging = paths.updates / L"Staging";
    paths.backups = paths.updates / L"Backups";
    paths.appDirectory = paths.root / L"App";
    paths.userData = paths.root / L"UserData";
    paths.logs = paths.updates / L"Logs";
    return paths;
}

bool ensureDirectory(const fs::path &path, std::wstring &error)
{
    std::error_code ec;
    fs::create_directories(path, ec);
    if (ec || !fs::is_directory(path, ec)) {
        error = L"Could not create directory: " + path.wstring();
        if (ec)
            error += L" (" + widenUtf8(ec.message()) + L")";
        return false;
    }
    return true;
}

class FlatJsonParser {
public:
    explicit FlatJsonParser(const std::string &source) : source_(source) {}

    bool parse(std::map<std::string, std::string> &result)
    {
        skipWhitespace();
        if (!consume('{'))
            return false;
        skipWhitespace();
        if (consume('}')) {
            skipWhitespace();
            return position_ == source_.size();
        }

        for (;;) {
            std::string key;
            if (!parseString(key))
                return false;
            skipWhitespace();
            if (!consume(':'))
                return false;
            skipWhitespace();

            std::string value;
            if (peek() == '"') {
                if (!parseString(value))
                    return false;
            } else {
                const size_t start = position_;
                while (position_ < source_.size() && source_[position_] != ','
                       && source_[position_] != '}')
                    ++position_;
                size_t end = position_;
                while (end > start && std::isspace(
                           static_cast<unsigned char>(source_[end - 1])))
                    --end;
                size_t trimmedStart = start;
                while (trimmedStart < end && std::isspace(
                           static_cast<unsigned char>(source_[trimmedStart])))
                    ++trimmedStart;
                if (trimmedStart == end)
                    return false;
                value = source_.substr(trimmedStart, end - trimmedStart);
                if (value.find_first_of("[]{") != std::string::npos)
                    return false;
            }

            if (!result.emplace(key, value).second)
                return false;
            skipWhitespace();
            if (consume('}'))
                break;
            if (!consume(','))
                return false;
            skipWhitespace();
        }

        skipWhitespace();
        return position_ == source_.size();
    }

private:
    const std::string &source_;
    size_t position_ = 0;

    char peek() const
    {
        return position_ < source_.size() ? source_[position_] : '\0';
    }

    bool consume(char expected)
    {
        if (peek() != expected)
            return false;
        ++position_;
        return true;
    }

    void skipWhitespace()
    {
        while (position_ < source_.size()
               && std::isspace(static_cast<unsigned char>(source_[position_])))
            ++position_;
    }

    bool parseString(std::string &value)
    {
        skipWhitespace();
        if (!consume('"'))
            return false;
        value.clear();

        while (position_ < source_.size()) {
            const unsigned char ch = static_cast<unsigned char>(source_[position_++]);
            if (ch == '"')
                return true;
            if (ch < 0x20)
                return false;
            if (ch != '\\') {
                value.push_back(static_cast<char>(ch));
                continue;
            }
            if (position_ >= source_.size())
                return false;

            const char escaped = source_[position_++];
            switch (escaped) {
            case '"': value.push_back('"'); break;
            case '\\': value.push_back('\\'); break;
            case '/': value.push_back('/'); break;
            case 'b': value.push_back('\b'); break;
            case 'f': value.push_back('\f'); break;
            case 'n': value.push_back('\n'); break;
            case 'r': value.push_back('\r'); break;
            case 't': value.push_back('\t'); break;
            case 'u':
                // This feed's machine-readable fields are ASCII. Consume a valid
                // Unicode escape without treating its four hex digits as syntax.
                if (position_ + 4 > source_.size())
                    return false;
                for (int i = 0; i < 4; ++i) {
                    if (!std::isxdigit(static_cast<unsigned char>(source_[position_++])))
                        return false;
                }
                value.push_back('?');
                break;
            default:
                return false;
            }
        }
        return false;
    }
};

std::optional<std::string> field(const std::map<std::string, std::string> &object,
                                 const std::string &name)
{
    const auto found = object.find(name);
    if (found == object.end())
        return std::nullopt;
    return found->second;
}

bool validVersion(const std::string &version)
{
    int components = 0;
    size_t start = 0;
    while (start < version.size()) {
        const size_t dot = version.find('.', start);
        const size_t end = dot == std::string::npos ? version.size() : dot;
        if (end == start || end - start > 5)
            return false;
        for (size_t i = start; i < end; ++i) {
            if (!std::isdigit(static_cast<unsigned char>(version[i])))
                return false;
        }
        ++components;
        if (dot == std::string::npos)
            break;
        start = dot + 1;
    }
    return components == 3 && !version.empty() && version.back() != '.';
}

bool validSha256(const std::string &hash)
{
    if (hash.size() != 64)
        return false;
    return std::all_of(hash.begin(), hash.end(), [](unsigned char ch) {
        return std::isxdigit(ch) != 0;
    });
}

std::string lowerAscii(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return value;
}

bool parsePositiveSize(const std::string &text, unsigned long long &size)
{
    if (text.empty())
        return false;
    size = 0;
    for (const char ch : text) {
        if (ch < '0' || ch > '9')
            return false;
        const unsigned int digit = static_cast<unsigned int>(ch - '0');
        if (size > (kMaximumExecutableBytes - digit) / 10)
            return false;
        size = size * 10 + digit;
    }
    return size > 0 && size <= kMaximumExecutableBytes;
}

bool readHttp(const std::wstring &url, unsigned long long maximumBytes,
              const std::function<bool(const char *, size_t)> &consume,
              unsigned long long &totalBytes, std::wstring &error,
              const std::function<void(unsigned long long)> &progress = {})
{
    URL_COMPONENTS parts{};
    parts.dwStructSize = sizeof(parts);
    parts.dwSchemeLength = static_cast<DWORD>(-1);
    parts.dwHostNameLength = static_cast<DWORD>(-1);
    parts.dwUrlPathLength = static_cast<DWORD>(-1);
    parts.dwExtraInfoLength = static_cast<DWORD>(-1);

    if (!WinHttpCrackUrl(url.c_str(), 0, 0, &parts)
        || parts.nScheme != INTERNET_SCHEME_HTTPS) {
        error = L"Only valid HTTPS URLs are allowed.";
        return false;
    }

    const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
    std::wstring path(parts.lpszUrlPath, parts.dwUrlPathLength);
    if (parts.dwExtraInfoLength && parts.lpszExtraInfo)
        path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
    if (path.empty())
        path = L"/";

    HINTERNET session = WinHttpOpen(L"ArgonUpdater/1.0",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) {
        error = windowsError(L"Could not initialise HTTPS");
        return false;
    }
    WinHttpSetTimeouts(session, 10000, 10000, 15000, 20000);

    HINTERNET connection = WinHttpConnect(session, host.c_str(), parts.nPort, 0);
    if (!connection) {
        error = windowsError(L"Could not connect to the release host");
        WinHttpCloseHandle(session);
        return false;
    }

    HINTERNET request = WinHttpOpenRequest(connection, L"GET", path.c_str(),
        nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
        WINHTTP_FLAG_SECURE);
    if (!request) {
        error = windowsError(L"Could not create HTTPS request");
        WinHttpCloseHandle(connection);
        WinHttpCloseHandle(session);
        return false;
    }

    bool okay = false;
    totalBytes = 0;
    if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0)
        || !WinHttpReceiveResponse(request, nullptr)) {
        error = windowsError(L"HTTPS request failed");
    } else {
        DWORD status = 0;
        DWORD statusSize = sizeof(status);
        if (!WinHttpQueryHeaders(request,
                WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                WINHTTP_HEADER_NAME_BY_INDEX, &status, &statusSize,
                WINHTTP_NO_HEADER_INDEX)) {
            error = windowsError(L"Could not read the HTTP response status");
        } else if (status != 200) {
            error = L"Server returned HTTP " + std::to_wstring(status)
                + L". The metadata or release asset may not be publicly accessible.";
        } else {
            okay = true;
            for (;;) {
                DWORD available = 0;
                if (!WinHttpQueryDataAvailable(request, &available)) {
                    error = windowsError(L"Could not read the HTTPS response");
                    okay = false;
                    break;
                }
                if (available == 0)
                    break;

                std::vector<char> buffer(std::min<DWORD>(available, 64 * 1024));
                DWORD received = 0;
                if (!WinHttpReadData(request, buffer.data(),
                                     static_cast<DWORD>(buffer.size()), &received)) {
                    error = windowsError(L"Could not download the response data");
                    okay = false;
                    break;
                }
                if (received == 0)
                    break;
                if (received > maximumBytes || totalBytes > maximumBytes - received) {
                    error = L"Download exceeded the permitted size limit.";
                    okay = false;
                    break;
                }
                if (!consume(buffer.data(), received)) {
                    if (error.empty())
                        error = L"Could not write downloaded data.";
                    okay = false;
                    break;
                }
                totalBytes += received;
                if (progress)
                    progress(totalBytes);
            }
        }
    }

    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    return okay;
}

bool fetchMetadata(std::string &text, std::wstring &error)
{
    unsigned long long bytes = 0;
    text.clear();
    const bool okay = readHttp(widenUtf8(ARGON_APP_DIRECTORY_URL),
        kMaximumMetadataBytes,
        [&text](const char *data, size_t count) {
            text.append(data, count);
            return true;
        }, bytes, error);
    if (okay && text.empty()) {
        error = L"directory.json was empty.";
        return false;
    }
    return okay;
}

bool parseRelease(const std::string &text, AppRelease &release,
                  std::wstring &error)
{
    std::map<std::string, std::string> metadata;
    FlatJsonParser parser(text);
    if (!parser.parse(metadata)) {
        error = L"directory.json is not a valid flat JSON object.";
        return false;
    }

    const auto schema = field(metadata, "schemaVersion");
    const auto product = field(metadata, "product");
    const auto channel = field(metadata, "channel");
    const auto targetBranch = field(metadata, "targetBranch");
    const auto version = field(metadata, "version");
    const auto fileName = field(metadata, "fileName");
    const auto packageUrl = field(metadata, "packageUrl");
    const auto hash = field(metadata, "sha256");
    const auto size = field(metadata, "sizeBytes");

    if (!schema || *schema != "1" || !product || *product != "Argon"
        || !channel || *channel != "intermediate"
        || !targetBranch || *targetBranch != "updater-intermediate") {
        error = L"directory.json must identify schema 1, Argon intermediate, and targetBranch updater-intermediate.";
        return false;
    }
    if (!version || !validVersion(*version)) {
        error = L"directory.json version must use MAJOR.MINOR.PATCH, for example 0.2.0.";
        return false;
    }
    if (!fileName || *fileName != "Argon.exe") {
        error = L"directory.json fileName must be exactly Argon.exe.";
        return false;
    }
    if (!packageUrl || packageUrl->empty() || !hash || !validSha256(*hash) || !size) {
        error = L"No complete app release is published in directory.json yet.";
        return false;
    }

    unsigned long long parsedSize = 0;
    if (!parsePositiveSize(*size, parsedSize)) {
        error = L"directory.json sizeBytes is invalid or exceeds 512 MiB.";
        return false;
    }

    const std::string tag = "app-v" + *version;
    const std::string expectedUrl =
        "https://github.com/mnotion/argon.updater/releases/download/"
        + tag + "/Argon.exe";
    if (*packageUrl != expectedUrl) {
        error = L"packageUrl must point to the Argon.exe asset in this release: "
            + widenUtf8(expectedUrl);
        return false;
    }

    release.version = *version;
    release.packageUrl = *packageUrl;
    release.sha256 = lowerAscii(*hash);
    release.sizeBytes = parsedSize;
    return true;
}

bool sha256File(const fs::path &path, std::string &hexHash,
                std::wstring &error)
{
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    std::vector<UCHAR> hashObject;
    std::vector<UCHAR> digest;
    HANDLE file = INVALID_HANDLE_VALUE;
    bool okay = false;

    NTSTATUS status = BCryptOpenAlgorithmProvider(
        &algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
    if (status < 0) {
        error = L"Could not initialise SHA-256 verification.";
        return false;
    }

    DWORD objectLength = 0;
    DWORD returned = 0;
    DWORD digestLength = 0;
    status = BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
        reinterpret_cast<PUCHAR>(&objectLength), sizeof(objectLength),
        &returned, 0);
    if (status >= 0) {
        status = BCryptGetProperty(algorithm, BCRYPT_HASH_LENGTH,
            reinterpret_cast<PUCHAR>(&digestLength), sizeof(digestLength),
            &returned, 0);
    }
    if (status < 0 || digestLength != 32) {
        error = L"Could not configure SHA-256 verification.";
        BCryptCloseAlgorithmProvider(algorithm, 0);
        return false;
    }

    hashObject.resize(objectLength);
    digest.resize(digestLength);
    status = BCryptCreateHash(algorithm, &hash, hashObject.data(),
                              objectLength, nullptr, 0, 0);
    if (status < 0) {
        error = L"Could not create SHA-256 hash.";
        BCryptCloseAlgorithmProvider(algorithm, 0);
        return false;
    }

    file = CreateFileW(path.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = windowsError(L"Could not open downloaded executable for validation");
    } else {
        std::vector<UCHAR> buffer(64 * 1024);
        okay = true;
        for (;;) {
            DWORD bytesRead = 0;
            if (!ReadFile(file, buffer.data(),
                          static_cast<DWORD>(buffer.size()), &bytesRead, nullptr)) {
                error = windowsError(L"Could not read downloaded executable for validation");
                okay = false;
                break;
            }
            if (bytesRead == 0)
                break;
            status = BCryptHashData(hash, buffer.data(), bytesRead, 0);
            if (status < 0) {
                error = L"SHA-256 calculation failed.";
                okay = false;
                break;
            }
        }
        CloseHandle(file);
    }

    if (okay) {
        status = BCryptFinishHash(hash, digest.data(), digestLength, 0);
        if (status < 0) {
            error = L"Could not finish SHA-256 validation.";
            okay = false;
        }
    }

    if (okay) {
        static constexpr char digits[] = "0123456789abcdef";
        hexHash.clear();
        hexHash.reserve(digest.size() * 2);
        for (const UCHAR byte : digest) {
            hexHash.push_back(digits[(byte >> 4) & 0x0F]);
            hexHash.push_back(digits[byte & 0x0F]);
        }
    }

    if (hash)
        BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return okay;
}

bool fileMatchesRelease(const fs::path &path, const AppRelease &release)
{
    std::error_code ec;
    if (!fs::is_regular_file(path, ec) || ec)
        return false;
    const auto size = fs::file_size(path, ec);
    if (ec || size != release.sizeBytes)
        return false;
    std::string actualHash;
    std::wstring ignored;
    return sha256File(path, actualHash, ignored)
        && lowerAscii(actualHash) == release.sha256;
}

bool downloadRelease(const Paths &paths, const AppRelease &release,
                     fs::path &finalPath, std::wstring &error)
{
    const std::wstring folderName = L"app-v" + widenUtf8(release.version);
    const fs::path releaseDirectory = paths.downloads / folderName;
    finalPath = releaseDirectory / L"Argon.exe";

    if (fileMatchesRelease(finalPath, release))
        return true;

    if (!ensureDirectory(releaseDirectory, error))
        return false;

    fs::path temporary = releaseDirectory / L"Argon.exe.download.tmp";
    if (GetFileAttributesW(temporary.c_str()) != INVALID_FILE_ATTRIBUTES) {
        if (!DeleteFileW(temporary.c_str())) {
            error = windowsError(L"Could not remove an incomplete previous download");
            return false;
        }
    }

    HANDLE output = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
        CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (output == INVALID_HANDLE_VALUE) {
        error = windowsError(L"Could not create the download file");
        return false;
    }

    unsigned long long downloaded = 0;
    int lastReportedProgress = -1;
    const bool received = readHttp(widenUtf8(release.packageUrl), release.sizeBytes,
        [output, &error](const char *data, size_t count) {
            size_t offset = 0;
            while (offset < count) {
                const DWORD request = static_cast<DWORD>(
                    std::min<size_t>(count - offset, 64 * 1024));
                DWORD written = 0;
                if (!WriteFile(output, data + offset, request, &written, nullptr)
                    || written != request) {
                    error = windowsError(L"Could not write the downloaded executable");
                    return false;
                }
                offset += written;
            }
            return true;
        }, downloaded, error,
        [&](unsigned long long bytes) {
            if (!g_silentUiMode || g_statusFile.empty() || release.sizeBytes == 0)
                return;
            const int percent = static_cast<int>((bytes * 100ULL) / release.sizeBytes);
            if (percent != lastReportedProgress) {
                lastReportedProgress = percent;
                writeUiStatus("downloading", L"Downloading and verifying Argon update…",
                              percent, release.version, finalPath, L"");
            }
        });

    bool flushed = received;
    if (flushed && !FlushFileBuffers(output)) {
        error = windowsError(L"Could not flush the downloaded executable");
        flushed = false;
    }
    CloseHandle(output);

    if (!flushed || downloaded != release.sizeBytes) {
        if (flushed)
            error = L"Downloaded byte count does not match directory.json sizeBytes.";
        DeleteFileW(temporary.c_str());
        return false;
    }

    std::string actualHash;
    if (!sha256File(temporary, actualHash, error)
        || lowerAscii(actualHash) != release.sha256) {
        if (error.empty())
            error = L"Downloaded executable failed SHA-256 validation.";
        DeleteFileW(temporary.c_str());
        return false;
    }

    if (!MoveFileExW(temporary.c_str(), finalPath.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        error = windowsError(L"Could not place the verified executable in Downloads");
        DeleteFileW(temporary.c_str());
        return false;
    }
    return true;
}

bool runDownload(fs::path &savedPath, AppRelease &release,
                  std::wstring &error, const std::string &expectedVersion = {})
{
    const auto paths = resolvePaths(error);
    if (!paths)
        return false;
    if (!ensureDirectory(paths->downloads, error))
        return false;

    std::string metadataText;
    if (!fetchMetadata(metadataText, error))
        return false;

    if (!parseRelease(metadataText, release, error))
        return false;

    if (!expectedVersion.empty() && release.version != expectedVersion) {
        error = L"The available package is version " + widenUtf8(release.version)
            + L", but Argon release metadata reports version "
            + widenUtf8(expectedVersion) + L". No files were changed.";
        return false;
    }

    if (!downloadRelease(*paths, release, savedPath, error))
        return false;
    return true;
}

constexpr int kInstallButton = 1001;
constexpr int kCancelButton = 1002;
constexpr int kRetryButton = 1003;
constexpr int kThanksButton = 1004;
constexpr int kFailureAcknowledgedButton = 1005;

std::wstring timeStamp(bool fileName = false)
{
    SYSTEMTIME now{};
    GetLocalTime(&now);
    wchar_t text[80]{};
    if (fileName) {
        std::swprintf(text, sizeof(text) / sizeof(text[0]),
                      L"%04u%02u%02u-%02u%02u%02u-%03u",
                      static_cast<unsigned int>(now.wYear),
                      static_cast<unsigned int>(now.wMonth),
                      static_cast<unsigned int>(now.wDay),
                      static_cast<unsigned int>(now.wHour),
                      static_cast<unsigned int>(now.wMinute),
                      static_cast<unsigned int>(now.wSecond),
                      static_cast<unsigned int>(now.wMilliseconds));
    } else {
        std::swprintf(text, sizeof(text) / sizeof(text[0]),
                      L"%04u-%02u-%02u %02u:%02u:%02u.%03u",
                      static_cast<unsigned int>(now.wYear),
                      static_cast<unsigned int>(now.wMonth),
                      static_cast<unsigned int>(now.wDay),
                      static_cast<unsigned int>(now.wHour),
                      static_cast<unsigned int>(now.wMinute),
                      static_cast<unsigned int>(now.wSecond),
                      static_cast<unsigned int>(now.wMilliseconds));
    }
    return text;
}

void addLog(std::vector<std::wstring> &entries, const std::wstring &entry)
{
    entries.push_back(L"[" + timeStamp() + L"] " + entry);
}

int showTaskDialog(const std::wstring &instruction,
                   const std::wstring &content,
                   const TASKDIALOG_BUTTON *buttons,
                   int buttonCount,
                   int defaultButton,
                   PCWSTR icon)
{
    TASKDIALOGCONFIG config{};
    config.cbSize = sizeof(config);
    config.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION;
    config.hwndParent = nullptr;
    config.hInstance = GetModuleHandleW(nullptr);
    config.pszWindowTitle = L"Argon Updater";
    config.pszMainInstruction = instruction.c_str();
    config.pszContent = content.c_str();
    config.pszMainIcon = icon;
    config.cButtons = static_cast<UINT>(buttonCount);
    config.pButtons = buttons;
    config.nDefaultButton = defaultButton;

    int clickedButton = 0;
    const HRESULT result = TaskDialogIndirect(&config, &clickedButton,
                                               nullptr, nullptr);
    return SUCCEEDED(result) ? clickedButton : 0;
}

bool fileExists(const fs::path &path)
{
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES
        && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool readyMarkerMatches(const fs::path &path)
{
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return false;

    constexpr char expected[] = "ready\n";
    char contents[sizeof(expected)]{};
    DWORD bytesRead = 0;
    const BOOL readOkay = ReadFile(file, contents, sizeof(contents),
                                   &bytesRead, nullptr);
    CloseHandle(file);
    return readOkay != FALSE
        && bytesRead == sizeof(expected) - 1
        && std::equal(expected, expected + sizeof(expected) - 1, contents);
}

bool removeFileIfPresent(const fs::path &path, std::wstring &error)
{
    if (!fileExists(path))
        return true;
    if (DeleteFileW(path.c_str()))
        return true;
    error = windowsError(L"Could not delete file " + path.wstring());
    return false;
}

bool pathIsWithin(const fs::path &candidate, const fs::path &protectedDirectory)
{
    std::error_code ec;
    fs::path normalizedCandidate = fs::absolute(candidate, ec);
    if (ec)
        return true; // Fail closed if a path cannot be normalized.
    normalizedCandidate = normalizedCandidate.lexically_normal();

    fs::path normalizedProtected = fs::absolute(protectedDirectory, ec);
    if (ec)
        return true;
    normalizedProtected = normalizedProtected.lexically_normal();

    auto candidatePart = normalizedCandidate.begin();
    for (auto protectedPart = normalizedProtected.begin();
         protectedPart != normalizedProtected.end();
         ++protectedPart, ++candidatePart) {
        if (candidatePart == normalizedCandidate.end()
            || _wcsicmp((*candidatePart).c_str(), (*protectedPart).c_str()) != 0) {
            return false;
        }
    }
    return true;
}

bool removeDirectoryTree(const Paths &paths, const fs::path &path,
                         std::wstring &error)
{
    // Refuse cleanup paths inside, equal to, or above persistent UserData or
    // App. Checking both directions also blocks a future attempt to delete the
    // installation root recursively, not only a direct UserData target.
    const bool overlapsUserData = pathIsWithin(path, paths.userData)
        || pathIsWithin(paths.userData, path);
    const bool overlapsApp = pathIsWithin(path, paths.appDirectory)
        || pathIsWithin(paths.appDirectory, path);
    if (overlapsUserData || overlapsApp) {
        error = L"Refusing recursive cleanup that overlaps user data or App: "
            + path.wstring();
        return false;
    }

    std::error_code ec;
    if (!fs::exists(path, ec))
        return !ec;
    fs::remove_all(path, ec);
    if (ec) {
        error = L"Could not remove directory " + path.wstring()
            + L": " + widenUtf8(ec.message());
        return false;
    }
    return true;
}

bool sameFileContents(const fs::path &left, const fs::path &right,
                      std::wstring &error)
{
    std::error_code ec;
    const auto leftSize = fs::file_size(left, ec);
    if (ec) {
        error = L"Could not read file size for " + left.wstring()
            + L": " + widenUtf8(ec.message());
        return false;
    }
    const auto rightSize = fs::file_size(right, ec);
    if (ec) {
        error = L"Could not read file size for " + right.wstring()
            + L": " + widenUtf8(ec.message());
        return false;
    }
    if (leftSize != rightSize) {
        error = L"File copy size did not match: " + left.wstring()
            + L" and " + right.wstring();
        return false;
    }

    std::string leftHash;
    std::string rightHash;
    if (!sha256File(left, leftHash, error)
        || !sha256File(right, rightHash, error)) {
        return false;
    }
    if (lowerAscii(leftHash) != lowerAscii(rightHash)) {
        error = L"File copy SHA-256 did not match: " + left.wstring()
            + L" and " + right.wstring();
        return false;
    }
    return true;
}

bool copyFile(const fs::path &source, const fs::path &destination,
              bool failIfDestinationExists, std::wstring &error)
{
    if (!ensureDirectory(destination.parent_path(), error))
        return false;
    if (!CopyFileW(source.c_str(), destination.c_str(),
                   failIfDestinationExists ? TRUE : FALSE)) {
        error = windowsError(L"Could not copy " + source.wstring()
                             + L" to " + destination.wstring());
        return false;
    }
    return true;
}

bool argonProcessRunning()
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
        return true; // Fail closed: never replace an executable if process state cannot be inspected.

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    bool found = false;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szExeFile, L"Argon.exe") == 0) {
                found = true;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return found;
}

bool waitForArgonToClose(bool silentUi = false)
{
    if (silentUi) {
        for (int elapsed = 0; elapsed < 45000; elapsed += 150) {
            if (!argonProcessRunning())
                return true;
            Sleep(150);
        }
        return !argonProcessRunning();
    }

    const TASKDIALOG_BUTTON buttons[] = {
        {kRetryButton, L"Try again"},
        {kCancelButton, L"Cancel"}
    };
    while (argonProcessRunning()) {
        const int choice = showTaskDialog(
            L"Close Argon before installing",
            L"Argon is currently running. Save your work, close Argon, "
            L"then select Try again. No application files have been changed.",
            buttons, 2, kRetryButton, TD_INFORMATION_ICON);
        if (choice != kRetryButton)
            return false;
    }
    return true;
}

class UpdateLock
{
public:
    UpdateLock() = default;
    UpdateLock(const UpdateLock &) = delete;
    UpdateLock &operator=(const UpdateLock &) = delete;

    ~UpdateLock()
    {
        if (handle_ != INVALID_HANDLE_VALUE) {
            CloseHandle(handle_);
            DeleteFileW(path_.c_str());
        }
    }

    bool acquire(const fs::path &path, std::wstring &error)
    {
        path_ = path;
        handle_ = CreateFileW(path_.c_str(), GENERIC_READ | GENERIC_WRITE,
                              0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
        if (handle_ == INVALID_HANDLE_VALUE) {
            if (GetLastError() == ERROR_FILE_EXISTS) {
                error = L"Another Argon update is already in progress.";
            } else {
                error = windowsError(L"Could not create the update lock");
            }
            return false;
        }
        return true;
    }

private:
    fs::path path_;
    HANDLE handle_ = INVALID_HANDLE_VALUE;
};

bool launchArgon(const fs::path &executable, const fs::path &workingDirectory,
                 const fs::path &readyFile, PROCESS_INFORMATION &process,
                 std::wstring &error)
{
    std::wstring commandLine = L"\"" + executable.wstring() + L"\"";
    if (!readyFile.empty())
        commandLine += L" --argon-update-ready-file \"" + readyFile.wstring() + L"\"";
    std::vector<wchar_t> mutableCommandLine(commandLine.begin(),
                                             commandLine.end());
    mutableCommandLine.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    process = {};
    if (!CreateProcessW(executable.c_str(), mutableCommandLine.data(),
                        nullptr, nullptr, FALSE, 0, nullptr,
                        workingDirectory.c_str(), &startup, &process)) {
        error = windowsError(L"Could not launch " + executable.wstring());
        return false;
    }
    return true;
}

bool stopProcess(PROCESS_INFORMATION &process,
                 std::vector<std::wstring> &entries)
{
    if (process.hProcess) {
        DWORD state = WaitForSingleObject(process.hProcess, 0);
        if (state == WAIT_TIMEOUT) {
            if (!TerminateProcess(process.hProcess, 1)
                && WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
                addLog(entries, windowsError(L"Could not stop the failed new Argon process"));
                return false;
            }
            state = WaitForSingleObject(process.hProcess, 5000);
            if (state != WAIT_OBJECT_0) {
                addLog(entries, L"The failed Argon process did not exit after termination was requested.");
                return false;
            }
        } else if (state != WAIT_OBJECT_0) {
            addLog(entries, windowsError(L"Could not inspect the new Argon process"));
            return false;
        }
    }

    if (process.hThread)
        CloseHandle(process.hThread);
    if (process.hProcess)
        CloseHandle(process.hProcess);
    process = {};
    return true;
}

bool launchPreservedArgon(const Paths &paths,
                          std::vector<std::wstring> &entries)
{
    const fs::path installedExe = paths.appDirectory / L"Argon.exe";
    if (argonProcessRunning()) {
        addLog(entries, L"Argon is already running; no second copy was launched.");
        return true;
    }
    if (!fileExists(installedExe)) {
        addLog(entries, L"The installed Argon.exe is unavailable, so the previous version could not be launched.");
        return false;
    }

    PROCESS_INFORMATION process{};
    std::wstring launchError;
    if (!launchArgon(installedExe, paths.appDirectory, {}, process, launchError)) {
        addLog(entries, L"Could not relaunch the preserved version: " + launchError);
        return false;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    addLog(entries, L"Launched the preserved Argon.exe.");
    return true;
}

bool writeFailureLog(const Paths &paths,
                     const std::vector<std::wstring> &entries,
                     fs::path &logPath, std::wstring &error)
{
    if (!ensureDirectory(paths.logs, error))
        return false;

    logPath = paths.logs / (L"ArgonUpdateFailure-" + timeStamp(true) + L".log");
    std::wstring text = L"Argon updater failure log\r\n";
    for (const auto &entry : entries)
        text += entry + L"\r\n";

    const int needed = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (needed <= 0) {
        error = L"Could not encode the update log as UTF-8.";
        return false;
    }
    std::string utf8(static_cast<size_t>(needed), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(),
        static_cast<int>(text.size()), utf8.data(), needed, nullptr, nullptr) <= 0) {
        error = L"Could not encode the update log as UTF-8.";
        return false;
    }

    HANDLE output = CreateFileW(logPath.c_str(), GENERIC_WRITE, 0, nullptr,
                                CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (output == INVALID_HANDLE_VALUE) {
        error = windowsError(L"Could not create the failure log");
        return false;
    }

    static constexpr char bom[] = {'\xEF', '\xBB', '\xBF'};
    DWORD written = 0;
    bool okay = WriteFile(output, bom, sizeof(bom), &written, nullptr)
        && written == sizeof(bom);
    size_t offset = 0;
    while (okay && offset < utf8.size()) {
        const DWORD request = static_cast<DWORD>(
            std::min<size_t>(utf8.size() - offset, 64 * 1024));
        written = 0;
        if (!WriteFile(output, utf8.data() + offset, request, &written, nullptr)
            || written != request) {
            okay = false;
            break;
        }
        offset += written;
    }
    if (okay)
        okay = FlushFileBuffers(output) != FALSE;
    CloseHandle(output);

    if (!okay) {
        error = L"Could not finish writing the failure log.";
        DeleteFileW(logPath.c_str());
        return false;
    }
    return true;
}

void showFailureAndLog(const Paths *paths,
                       std::vector<std::wstring> &entries,
                       const std::wstring &reason,
                       bool originalReady)
{
    addLog(entries, L"Failure summary: " + reason);
    addLog(entries, originalReady
        ? L"The original executable was preserved or restored."
        : L"Automatic rollback could not be confirmed; the backup and staging files were retained.");

    if (g_silentUiMode) {
        writeUiStatus("failed", L"Argon update failed. The previous version was preserved or restored.",
                      0, g_expectedVersion, fs::path(), reason);
        if (paths) {
            fs::path ignoredPath;
            std::wstring ignoredError;
            writeFailureLog(*paths, entries, ignoredPath, ignoredError);
        }
        return;
    }

    std::wstring content = reason + L"\r\n\r\n";
    content += originalReady
        ? L"The previous Argon version was kept or restored and was launched again when possible.\r\n"
        : L"Automatic rollback could not be confirmed. Do not delete the backup or staging files.\r\n";
    content += L"Click It's okay man to save the diagnostic log.";

    const TASKDIALOG_BUTTON buttons[] = {
        {kFailureAcknowledgedButton, L"It's okay man"}
    };
    const int choice = showTaskDialog(
        L"Something bad happened...", content, buttons, 1,
        kFailureAcknowledgedButton, TD_ERROR_ICON);
    if (choice != kFailureAcknowledgedButton)
        return;

    if (!paths) {
        MessageBoxW(nullptr,
            L"The diagnostic log could not be saved because the updater could not resolve the Argon-sim folder.",
            L"Argon Updater", MB_OK | MB_ICONERROR);
        return;
    }

    fs::path logPath;
    std::wstring logError;
    if (!writeFailureLog(*paths, entries, logPath, logError)) {
        MessageBoxW(nullptr,
            (L"The update failed, and the diagnostic log could not be saved.\r\n\r\n"
             + logError).c_str(),
            L"Argon Updater", MB_OK | MB_ICONERROR);
    } else {
        MessageBoxW(nullptr,
            (L"Diagnostic log saved to:\r\n" + logPath.wstring()).c_str(),
            L"Argon Updater", MB_OK | MB_ICONINFORMATION);
    }
}

bool restoreBackup(const fs::path &backup,
                   const fs::path &installedExe,
                   std::vector<std::wstring> &entries,
                   std::wstring &error)
{
    if (!fileExists(backup)) {
        error = L"The previous executable backup is missing: " + backup.wstring();
        addLog(entries, error);
        return false;
    }
    if (fileExists(installedExe) && !DeleteFileW(installedExe.c_str())) {
        error = windowsError(L"Could not remove the failed replacement before rollback");
        addLog(entries, L"Rollback could not remove the new executable: " + error);
        return false;
    }
    if (!copyFile(backup, installedExe, true, error)) {
        addLog(entries, L"Rollback copy failed: " + error);
        return false;
    }
    std::wstring compareError;
    if (!sameFileContents(backup, installedExe, compareError)) {
        error = L"Rollback verification failed: " + compareError;
        addLog(entries, error);
        return false;
    }
    addLog(entries, L"Rollback succeeded; the original Argon.exe was restored and SHA-256 compared with the backup.");
    return true;
}

bool applyUpdate(const Paths &paths,
                 const fs::path &downloadedExe,
                 const AppRelease &release,
                 std::vector<std::wstring> &entries,
                 std::wstring &failure,
                 bool &originalReady,
                 fs::path &backupDirectory,
                 fs::path &launchReadyFile)
{
    // Keep installation strictly executable-only. Persistent user files are
    // rooted at <root>\\UserData, alongside (not inside) App. The transaction
    // may replace App\\Argon.exe and clean its own Updates staging/backups,
    // but must never replace App as a directory or recursively touch UserData.
    const fs::path installedExe = paths.appDirectory / L"Argon.exe";
    const fs::path stableDirectory = paths.staging / L"Stable";
    const fs::path outdatedDirectory = paths.staging / L"Outdated";
    const fs::path stableExe = stableDirectory / L"Argon.exe";
    const fs::path outdatedExe = outdatedDirectory / L"Argon.exe";
    const std::wstring transactionId = L"attempt-" + timeStamp(true);
    backupDirectory = paths.backups / transactionId;
    launchReadyFile = paths.staging / (L"launch-ready-" + timeStamp(true) + L".txt");

    bool originalMoved = false;
    bool stagingStarted = false;
    PROCESS_INFORMATION newProcess{};
    bool processStarted = false;
    originalReady = fileExists(installedExe);

    auto fail = [&](const std::wstring &reason) {
        failure = reason;
        addLog(entries, L"Installation failed: " + reason);

        bool stopped = true;
        if (processStarted)
            stopped = stopProcess(newProcess, entries);

        if (originalMoved) {
            if (!stopped) {
                originalReady = false;
                failure += L"\r\nThe new process could not be stopped; rollback was not attempted while it may still be using the executable.";
                addLog(entries, failure);
                return false;
            }

            std::wstring rollbackError;
            originalReady = restoreBackup(backupDirectory / L"Argon.exe",
                                          installedExe, entries,
                                          rollbackError);
            if (!originalReady)
                failure += L"\r\nRollback failed: " + rollbackError;
        } else {
            originalReady = fileExists(installedExe);
        }

        // Remove failed staged copies only when the previous executable is
        // confirmed present again. Preserve all recovery files if rollback failed.
        if (stagingStarted && originalReady) {
            std::wstring cleanupError;
            if (!removeDirectoryTree(paths, stableDirectory, cleanupError))
                addLog(entries, L"Could not clean failed Staging\\Stable: " + cleanupError);
            cleanupError.clear();
            if (!removeDirectoryTree(paths, outdatedDirectory, cleanupError))
                addLog(entries, L"Could not clean failed Staging\\Outdated: " + cleanupError);
        }
        return false;
    };

    if (!originalReady)
        return fail(L"The installed executable was not found at " + installedExe.wstring());
    if (!fileMatchesRelease(downloadedExe, release))
        return fail(L"The downloaded executable no longer matches directory.json sizeBytes and SHA-256.");

    if (!removeDirectoryTree(paths, stableDirectory, failure)
        || !removeDirectoryTree(paths, outdatedDirectory, failure))
        return fail(failure);
    if (!ensureDirectory(stableDirectory, failure)
        || !ensureDirectory(outdatedDirectory, failure)
        || !ensureDirectory(backupDirectory, failure))
        return fail(failure);
    stagingStarted = true;
    addLog(entries, L"Created Staging\\Stable, Staging\\Outdated, and a transaction-specific backup folder.");

    if (!MoveFileExW(downloadedExe.c_str(), stableExe.c_str(), MOVEFILE_WRITE_THROUGH)) {
        return fail(windowsError(L"Could not move the verified download into Staging\\Stable"));
    }
    if (!fileMatchesRelease(stableExe, release))
        return fail(L"Staging\\Stable\\Argon.exe failed package size or SHA-256 verification.");
    addLog(entries, L"Moved the verified download into Staging\\Stable and re-verified it.");

    if (!MoveFileExW(installedExe.c_str(), (backupDirectory / L"Argon.exe").c_str(),
                     MOVEFILE_WRITE_THROUGH)) {
        return fail(windowsError(L"Could not move the installed Argon.exe into Updates\\Backups"));
    }
    originalMoved = true;
    addLog(entries, L"Moved the installed Argon.exe into the transaction backup.");

    if (!copyFile(backupDirectory / L"Argon.exe", outdatedExe, false, failure))
        return fail(failure);
    std::wstring compareError;
    if (!sameFileContents(backupDirectory / L"Argon.exe", outdatedExe, compareError))
        return fail(L"Staging\\Outdated\\Argon.exe did not match the backup: " + compareError);
    addLog(entries, L"Copied the backed-up original into Staging\\Outdated and verified byte-for-byte SHA-256 equivalence.");

    if (!copyFile(stableExe, installedExe, true, failure))
        return fail(failure);
    if (!fileMatchesRelease(installedExe, release))
        return fail(L"The new executable copied into App failed size or SHA-256 verification.");
    addLog(entries, L"Copied Staging\\Stable\\Argon.exe into App and verified the installed executable.");

    std::wstring markerDeleteError;
    if (!removeFileIfPresent(launchReadyFile, markerDeleteError))
        return fail(markerDeleteError);

    std::wstring launchError;
    if (!launchArgon(installedExe, paths.appDirectory, launchReadyFile,
                     newProcess, launchError))
        return fail(launchError);
    processStarted = true;
    addLog(entries, L"Launched the new executable with a one-time application-ready marker.");

    bool ready = false;
    for (int elapsed = 0; elapsed < 20000; elapsed += 200) {
        if (readyMarkerMatches(launchReadyFile)) {
            ready = true;
            break;
        }
        const DWORD state = WaitForSingleObject(newProcess.hProcess, 0);
        if (state == WAIT_OBJECT_0) {
            DWORD exitCode = 0;
            GetExitCodeProcess(newProcess.hProcess, &exitCode);
            return fail(L"The new Argon process exited before the main window became ready. Exit code: "
                        + std::to_wstring(exitCode));
        }
        if (state != WAIT_TIMEOUT)
            return fail(windowsError(L"Could not wait for the new Argon process"));
        Sleep(200);
    }
    if (!ready)
        return fail(L"The new Argon application did not write a valid readiness marker after its main QML window loaded within 20 seconds.");

    CloseHandle(newProcess.hThread);
    CloseHandle(newProcess.hProcess);
    newProcess = {};
    processStarted = false;
    addLog(entries, L"The new Argon application reported that its main QML window loaded successfully.");

    std::wstring ignored;
    if (!removeFileIfPresent(launchReadyFile, ignored))
        addLog(entries, L"Warning: the temporary launch-ready marker could not be removed: " + ignored);
    return true;
}

void cleanupAfterAcknowledgedSuccess(const Paths &paths,
                                     const fs::path &backupDirectory,
                                     const fs::path &launchReadyFile,
                                     std::vector<std::wstring> &entries)
{
    std::wstring error;
    if (!removeDirectoryTree(paths, backupDirectory, error))
        addLog(entries, L"Warning: old-version backup could not be deleted: " + error);
    else
        addLog(entries, L"Deleted the old executable backup after the user acknowledged the successful update.");

    error.clear();
    if (!removeDirectoryTree(paths, paths.staging / L"Stable", error))
        addLog(entries, L"Warning: Staging\\Stable could not be deleted: " + error);
    else
        addLog(entries, L"Deleted Staging\\Stable.");

    error.clear();
    if (!removeDirectoryTree(paths, paths.staging / L"Outdated", error))
        addLog(entries, L"Warning: Staging\\Outdated could not be deleted: " + error);
    else
        addLog(entries, L"Deleted Staging\\Outdated.");

    error.clear();
    if (!removeFileIfPresent(launchReadyFile, error))
        addLog(entries, L"Warning: the launch-ready marker could not be deleted: " + error);
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    int argumentCount = 0;
    LPWSTR *arguments = CommandLineToArgvW(GetCommandLineW(), &argumentCount);
    std::wstring expectedVersionWide;
    std::wstring statusFileWide;
    if (arguments) {
        for (int i = 1; i < argumentCount; ++i) {
            const std::wstring argument = arguments[i];
            if (argument == L"--download-only")
                g_downloadOnlyMode = true;
            else if (argument == L"--install-downloaded")
                g_installOnlyMode = true;
            else if (argument == L"--expected-version" && i + 1 < argumentCount)
                expectedVersionWide = arguments[++i];
            else if (argument == L"--status-file" && i + 1 < argumentCount)
                statusFileWide = arguments[++i];
        }
        LocalFree(arguments);
    }
    g_silentUiMode = g_downloadOnlyMode || g_installOnlyMode;
    g_expectedVersion = narrowUtf8(expectedVersionWide);
    if (!statusFileWide.empty())
        g_statusFile = fs::path(statusFileWide);

    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&controls);

    std::vector<std::wstring> entries;
    addLog(entries, L"ArgonUpdater started.");
    std::wstring error;
    fs::path downloadedExe;
    AppRelease release;
    if (g_silentUiMode)
        writeUiStatus(g_downloadOnlyMode ? "downloading" : "installing",
                      g_downloadOnlyMode ? L"Preparing secure download of Argon update…"
                                         : L"Preparing the replacement transaction…",
                      0, g_expectedVersion, fs::path(), L"");

    if (!runDownload(downloadedExe, release, error, g_expectedVersion)) {
        addLog(entries, L"Download or metadata validation failed: " + error);
        std::wstring pathError;
        const auto paths = resolvePaths(pathError);
        bool originalReady = false;
        if (g_silentUiMode) {
            writeUiStatus("failed", L"Argon could not download the requested update.",
                          0, g_expectedVersion, fs::path(), error);
            if (g_installOnlyMode && paths) {
                originalReady = fileExists(paths->appDirectory / L"Argon.exe");
                if (originalReady)
                    launchPreservedArgon(*paths, entries);
            }
            return 2;
        }
        if (paths) {
            originalReady = fileExists(paths->appDirectory / L"Argon.exe");
            if (originalReady)
                launchPreservedArgon(*paths, entries);
            else
                addLog(entries, L"No original App\\Argon.exe was found to relaunch.");
        } else {
            addLog(entries, L"Could not resolve the update directory for recovery: " + pathError);
        }
        showFailureAndLog(paths ? &*paths : nullptr, entries, error, originalReady);
        return 2;
    }

    addLog(entries, L"Download verified: " + downloadedExe.wstring());
    addLog(entries, L"Published version: " + widenUtf8(release.version)
                    + L"; bytes: " + std::to_wstring(release.sizeBytes)
                    + L"; SHA-256: " + widenUtf8(release.sha256));

    if (g_downloadOnlyMode) {
        writeUiStatus("downloaded", L"Download complete. The package passed size and SHA-256 verification.",
                      100, release.version, downloadedExe, L"");
        return 0;
    }
    if (g_installOnlyMode)
        writeUiStatus("installing", L"Preparing the replacement transaction…",
                      0, release.version, downloadedExe, L"");

    std::wstring pathError;
    const auto paths = resolvePaths(pathError);
    if (!paths) {
        addLog(entries, L"Could not resolve install paths: " + pathError);
        if (g_silentUiMode) {
            writeUiStatus("failed", L"Could not resolve the Argon installation directory.",
                          0, release.version, downloadedExe, pathError);
            return 2;
        }
        showFailureAndLog(nullptr, entries, pathError, false);
        return 2;
    }

    const std::wstring installContent =
        L"A verified Argon update is ready to install.\r\n\r\n"
        L"Version: " + widenUtf8(release.version)
        + L"\r\nDownloaded file: " + downloadedExe.wstring()
        + L"\r\n\r\nArgon will be closed before replacement. The previous executable "
          L"will be backed up and restored automatically if the new app fails to load.";
    if (!g_silentUiMode) {
        const TASKDIALOG_BUTTON installButtons[] = {
            {kInstallButton, L"Install update"},
            {kCancelButton, L"Cancel"}
        };
        const int installChoice = showTaskDialog(
            L"Install Argon update?", installContent, installButtons, 2,
            kInstallButton, TD_INFORMATION_ICON);
        if (installChoice != kInstallButton)
            return 0;
    }

    UpdateLock lock;
    if (!ensureDirectory(paths->updates, error)
        || !lock.acquire(paths->updates / L"install-in-progress.lock", error)) {
        addLog(entries, L"Could not begin the install transaction: " + error);
        addLog(entries, L"Install lock or update directory setup failed before app files were changed.");
        if (g_silentUiMode) {
            writeUiStatus("failed", L"Could not start the install transaction.",
                          0, release.version, downloadedExe, error);
            launchPreservedArgon(*paths, entries);
            return 2;
        }
        showFailureAndLog(&*paths, entries, error, false);
        return 2;
    }

    if (!waitForArgonToClose(g_silentUiMode)) {
        error = L"Argon did not close within 45 seconds. No application files were changed.";
        addLog(entries, L"Installation was canceled while waiting for Argon to close.");
        if (g_silentUiMode) {
            writeUiStatus("failed", L"Argon did not close for installation.",
                          0, release.version, downloadedExe, error);
            if (!argonProcessRunning())
                launchPreservedArgon(*paths, entries);
            return 2;
        }
        return 0;
    }

    bool originalReady = false;
    fs::path backupDirectory;
    fs::path launchReadyFile;
    if (!applyUpdate(*paths, downloadedExe, release, entries, error,
                     originalReady, backupDirectory, launchReadyFile)) {
        if (g_silentUiMode) {
            writeUiStatus("failed", L"Installation failed. The previous version was restored when possible.",
                          0, release.version, downloadedExe, error);
            if (originalReady)
                launchPreservedArgon(*paths, entries);
            return 2;
        }
        if (originalReady)
            launchPreservedArgon(*paths, entries);
        showFailureAndLog(&*paths, entries, error, originalReady);
        return 2;
    }

    if (g_silentUiMode) {
        cleanupAfterAcknowledgedSuccess(*paths, backupDirectory, launchReadyFile, entries);
        writeUiStatus("installed", L"Argon was updated successfully and its main window reported ready.",
                      100, release.version, fs::path(), L"");
        return 0;
    }

    const std::wstring successContent =
        L"Argon " + widenUtf8(release.version)
        + L" has been installed and its main window reported ready.\r\n\r\n"
          L"The previous version will be removed only after you acknowledge this message.";
    const TASKDIALOG_BUTTON successButtons[] = {
        {kThanksButton, L"You're welcome"}
    };
    const int successChoice = showTaskDialog(
        L"Thanks for updating it \xD83D\xDE0A", successContent,
        successButtons, 1, kThanksButton, TD_INFORMATION_ICON);

    if (successChoice == kThanksButton)
        cleanupAfterAcknowledgedSuccess(*paths, backupDirectory,
                                        launchReadyFile, entries);

    return 0;
}
