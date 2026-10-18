#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <winhttp.h>
#include <bcrypt.h>
#include <winver.h>
#include <commctrl.h>

#include <algorithm>
#include <cctype>
#include <cwchar>
#include <array>
#include <cstdint>
#include <filesystem>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#ifndef ARGON_BOOTSTRAP_VERSION
#define ARGON_BOOTSTRAP_VERSION "1.0.0.0"
#endif

#ifndef ARGON_BOOTSTRAP_LATEST_URL
#define ARGON_BOOTSTRAP_LATEST_URL "https://raw.githubusercontent.com/mnotion/argon.updater/rel-config/bootstrap-latest.json?rev=3"
#endif

namespace fs = std::filesystem;

namespace {
constexpr wchar_t kWindowClass[] = L"ArgonBootstrapWindow";
constexpr UINT kCheckCompleteMessage = WM_APP + 14;
constexpr unsigned long long kMaximumMetadataBytes = 1024ULL * 1024ULL;
constexpr unsigned long long kMaximumUpdaterBytes = 512ULL * 1024ULL * 1024ULL;

HWND g_bootstrapStatus = nullptr;
HWND g_updaterStatus = nullptr;
HWND g_details = nullptr;
HFONT g_headingFont = nullptr;

struct CheckResult {
    std::wstring bootstrapStatus;
    std::wstring updaterStatus;
    std::wstring details;
};

struct Paths {
    fs::path root;
    fs::path bootstrapDirectory;
    fs::path updaterDirectory;
    fs::path updaterExecutable;
    fs::path downloadsDirectory;
    fs::path stagingDirectory;
    fs::path backupsDirectory;
    fs::path journalFile;
};

std::wstring widenUtf8(const std::string &value) {
    if (value.empty())
        return {};
    const int needed = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                            value.data(),
                                            static_cast<int>(value.size()),
                                            nullptr, 0);
    if (needed <= 0)
        return L"";
    std::wstring result(static_cast<size_t>(needed), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), needed);
    return result;
}

std::string narrowUtf8(const std::wstring &value) {
    if (value.empty())
        return {};
    const int needed = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                            value.data(),
                                            static_cast<int>(value.size()),
                                            nullptr, 0, nullptr, nullptr);
    if (needed <= 0)
        return {};
    std::string result(static_cast<size_t>(needed), '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                        static_cast<int>(value.size()), result.data(), needed,
                        nullptr, nullptr);
    return result;
}

std::wstring systemErrorText(const wchar_t *operation, DWORD code = GetLastError()) {
    wchar_t *messageBuffer = nullptr;
    const DWORD length = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
            | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<wchar_t *>(&messageBuffer), 0, nullptr);

    std::wstring message = length && messageBuffer
        ? std::wstring(messageBuffer, length)
        : L"Windows error " + std::to_wstring(code);
    if (messageBuffer)
        LocalFree(messageBuffer);
    while (!message.empty()
           && (message.back() == L'\r' || message.back() == L'\n'
               || message.back() == L' ')) {
        message.pop_back();
    }
    return std::wstring(operation) + L": " + message;
}

std::optional<Paths> resolvePaths(std::wstring &error) {
    std::vector<wchar_t> buffer(32768, L'\0');
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                             static_cast<DWORD>(buffer.size()));
    if (length == 0 || length >= buffer.size()) {
        error = systemErrorText(L"Could not locate Bootstrap.exe");
        return std::nullopt;
    }

    const fs::path executable(std::wstring(buffer.data(), length));
    Paths paths;
    paths.bootstrapDirectory = executable.parent_path();
    paths.root = paths.bootstrapDirectory.parent_path();
    if (paths.root.empty() || paths.root == paths.bootstrapDirectory) {
        error = L"Bootstrap.exe must be inside the Argon\\Bootstrap directory.";
        return std::nullopt;
    }
    paths.updaterDirectory = paths.root / L"Updater";
    paths.updaterExecutable = paths.updaterDirectory / L"ArgonUpdater.exe";
    const fs::path updates = paths.root / L"Updates";
    paths.downloadsDirectory = updates / L"Downloads";
    paths.stagingDirectory = updates / L"Staging";
    paths.backupsDirectory = updates / L"Backups";
    paths.journalFile = paths.stagingDirectory / L"updater-replacement.pending";
    return paths;
}

bool ensureDirectory(const fs::path &path, std::wstring &error) {
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

bool fileExists(const fs::path &path) {
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES
        && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool deleteFileIfPresent(const fs::path &path, std::wstring &error) {
    if (!fileExists(path))
        return true;
    if (DeleteFileW(path.c_str()))
        return true;
    error = systemErrorText(L"Could not remove temporary file");
    return false;
}

bool readFileText(const fs::path &path, std::string &text,
                  size_t maximumBytes, std::wstring &error) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                              FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = systemErrorText(L"Could not open file");
        return false;
    }

    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 0
        || static_cast<unsigned long long>(size.QuadPart) > maximumBytes) {
        CloseHandle(file);
        error = L"File size is invalid or exceeds the permitted limit.";
        return false;
    }

    text.clear();
    text.reserve(static_cast<size_t>(size.QuadPart));
    char buffer[8192];
    for (;;) {
        DWORD bytesRead = 0;
        if (!ReadFile(file, buffer, sizeof(buffer), &bytesRead, nullptr)) {
            CloseHandle(file);
            error = systemErrorText(L"Could not read file");
            return false;
        }
        if (bytesRead == 0)
            break;
        text.append(buffer, bytesRead);
        if (text.size() > maximumBytes) {
            CloseHandle(file);
            error = L"File exceeds the permitted size.";
            return false;
        }
    }
    CloseHandle(file);
    return true;
}

bool writeTextAtomically(const fs::path &path, const std::string &text,
                         std::wstring &error) {
    if (!ensureDirectory(path.parent_path(), error))
        return false;

    fs::path temporary = path;
    temporary += L".tmp";
    if (!deleteFileIfPresent(temporary, error))
        return false;

    HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = systemErrorText(L"Could not create transaction journal");
        return false;
    }

    size_t offset = 0;
    bool okay = true;
    while (offset < text.size()) {
        const DWORD request = static_cast<DWORD>(
            std::min<size_t>(text.size() - offset, 64 * 1024));
        DWORD written = 0;
        if (!WriteFile(file, text.data() + offset, request, &written, nullptr)
            || written != request) {
            okay = false;
            error = systemErrorText(L"Could not write transaction journal");
            break;
        }
        offset += written;
    }

    if (okay && !FlushFileBuffers(file)) {
        okay = false;
        error = systemErrorText(L"Could not flush transaction journal");
    }
    CloseHandle(file);

    if (!okay) {
        DeleteFileW(temporary.c_str());
        return false;
    }
    if (!MoveFileExW(temporary.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        error = systemErrorText(L"Could not activate transaction journal");
        DeleteFileW(temporary.c_str());
        return false;
    }
    return true;
}

class JsonObjectParser {
public:
    explicit JsonObjectParser(const std::string &text) : text_(text) {}

    bool parse(std::map<std::string, std::string> &result) {
        skipWhitespace();
        if (!consume('{'))
            return fail(L"JSON root must be an object.");
        skipWhitespace();
        if (consume('}')) {
            skipWhitespace();
            return position_ == text_.size() || fail(L"Unexpected text after JSON object.");
        }

        for (;;) {
            skipWhitespace();
            std::string key;
            if (!parseString(key))
                return fail(L"JSON object contains an invalid property name.");
            skipWhitespace();
            if (!consume(':'))
                return fail(L"JSON object property is missing a colon.");
            skipWhitespace();

            std::string scalar;
            bool isScalar = false;
            if (!parseValue(scalar, isScalar))
                return fail(L"JSON object contains an invalid value.");
            if (isScalar) {
                if (!result.emplace(key, scalar).second)
                    return fail(L"JSON object contains a duplicate property.");
            }
            skipWhitespace();
            if (consume('}'))
                break;
            if (!consume(','))
                return fail(L"JSON object is missing a comma.");
        }
        skipWhitespace();
        return position_ == text_.size() || fail(L"Unexpected text after JSON object.");
    }

    const std::wstring &error() const { return error_; }

private:
    const std::string &text_;
    size_t position_ = 0;
    std::wstring error_;

    bool fail(const wchar_t *message) {
        error_ = message;
        return false;
    }

    void skipWhitespace() {
        while (position_ < text_.size()
               && (text_[position_] == ' ' || text_[position_] == '\t'
                   || text_[position_] == '\r' || text_[position_] == '\n')) {
            ++position_;
        }
    }

    bool consume(char expected) {
        if (position_ >= text_.size() || text_[position_] != expected)
            return false;
        ++position_;
        return true;
    }

    static void appendUtf8(std::string &out, unsigned int codepoint) {
        if (codepoint <= 0x7F) {
            out.push_back(static_cast<char>(codepoint));
        } else if (codepoint <= 0x7FF) {
            out.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
            out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else if (codepoint <= 0xFFFF) {
            out.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
            out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
            out.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        }
    }

    bool parseString(std::string &out) {
        if (!consume('"'))
            return false;
        out.clear();
        while (position_ < text_.size()) {
            const unsigned char ch = static_cast<unsigned char>(text_[position_++]);
            if (ch == '"')
                return true;
            if (ch < 0x20)
                return false;
            if (ch != '\\') {
                out.push_back(static_cast<char>(ch));
                continue;
            }
            if (position_ >= text_.size())
                return false;
            const char escaped = text_[position_++];
            switch (escaped) {
            case '"': out.push_back('"'); break;
            case '\\': out.push_back('\\'); break;
            case '/': out.push_back('/'); break;
            case 'b': out.push_back('\b'); break;
            case 'f': out.push_back('\f'); break;
            case 'n': out.push_back('\n'); break;
            case 'r': out.push_back('\r'); break;
            case 't': out.push_back('\t'); break;
            case 'u': {
                if (position_ + 4 > text_.size())
                    return false;
                unsigned int codepoint = 0;
                for (int i = 0; i < 4; ++i) {
                    const char h = text_[position_++];
                    codepoint <<= 4;
                    if (h >= '0' && h <= '9') codepoint |= static_cast<unsigned int>(h - '0');
                    else if (h >= 'a' && h <= 'f') codepoint |= static_cast<unsigned int>(h - 'a' + 10);
                    else if (h >= 'A' && h <= 'F') codepoint |= static_cast<unsigned int>(h - 'A' + 10);
                    else return false;
                }
                appendUtf8(out, codepoint);
                break;
            }
            default:
                return false;
            }
        }
        return false;
    }

    bool parseValue(std::string &scalar, bool &isScalar) {
        skipWhitespace();
        isScalar = false;
        if (position_ >= text_.size())
            return false;
        const char first = text_[position_];

        if (first == '"') {
            isScalar = true;
            return parseString(scalar);
        }
        if (first == '{') {
            ++position_;
            skipWhitespace();
            if (consume('}'))
                return true;
            for (;;) {
                std::string key;
                if (!parseString(key))
                    return false;
                skipWhitespace();
                if (!consume(':'))
                    return false;
                std::string ignored;
                bool ignoredScalar = false;
                if (!parseValue(ignored, ignoredScalar))
                    return false;
                skipWhitespace();
                if (consume('}'))
                    return true;
                if (!consume(','))
                    return false;
                skipWhitespace();
            }
        }
        if (first == '[') {
            ++position_;
            skipWhitespace();
            if (consume(']'))
                return true;
            for (;;) {
                std::string ignored;
                bool ignoredScalar = false;
                if (!parseValue(ignored, ignoredScalar))
                    return false;
                skipWhitespace();
                if (consume(']'))
                    return true;
                if (!consume(','))
                    return false;
            }
        }

        const size_t start = position_;
        while (position_ < text_.size()) {
            const char ch = text_[position_];
            if (ch == ',' || ch == '}' || ch == ']' || ch == ' '
                || ch == '\t' || ch == '\r' || ch == '\n') {
                break;
            }
            ++position_;
        }
        if (position_ == start)
            return false;
        scalar = text_.substr(start, position_ - start);
        if (scalar != "true" && scalar != "false" && scalar != "null") {
            for (const char ch : scalar) {
                if (!((ch >= '0' && ch <= '9') || ch == '-' || ch == '+'
                      || ch == '.' || ch == 'e' || ch == 'E')) {
                    return false;
                }
            }
        }
        isScalar = true;
        return true;
    }
};

bool parseJson(const std::string &text, std::map<std::string, std::string> &fields,
               std::wstring &error) {
    JsonObjectParser parser(text);
    if (!parser.parse(fields)) {
        error = parser.error();
        return false;
    }
    return true;
}

std::optional<std::string> field(const std::map<std::string, std::string> &fields,
                                 const std::string &key) {
    const auto it = fields.find(key);
    if (it == fields.end())
        return std::nullopt;
    return it->second;
}

bool parseVersion(const std::string &value, std::array<unsigned long long, 4> &parts) {
    size_t start = 0;
    for (size_t i = 0; i < parts.size(); ++i) {
        const size_t end = value.find('.', start);
        if ((i < 3 && end == std::string::npos)
            || (i == 3 && end != std::string::npos)) {
            return false;
        }
        const size_t stop = end == std::string::npos ? value.size() : end;
        if (stop == start)
            return false;
        unsigned long long component = 0;
        for (size_t j = start; j < stop; ++j) {
            const char digit = value[j];
            if (digit < '0' || digit > '9')
                return false;
            const unsigned long long value = static_cast<unsigned long long>(digit - '0');
            if (component > (0xFFFFFFFFULL - value) / 10ULL)
                return false;
            component = component * 10ULL + value;
        }
        parts[i] = component;
        start = stop + 1;
    }
    return true;
}

std::optional<int> compareVersions(const std::string &left, const std::string &right) {
    std::array<unsigned long long, 4> a{}, b{};
    if (!parseVersion(left, a) || !parseVersion(right, b))
        return std::nullopt;
    for (size_t i = 0; i < a.size(); ++i) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
    }
    return 0;
}

std::optional<std::wstring> readPeVersion(const fs::path &path) {
    DWORD ignored = 0;
    const DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
    if (size == 0)
        return std::nullopt;
    std::vector<BYTE> data(size);
    if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data()))
        return std::nullopt;

    VS_FIXEDFILEINFO *info = nullptr;
    UINT infoSize = 0;
    if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void **>(&info), &infoSize)
        || !info || infoSize < sizeof(VS_FIXEDFILEINFO)
        || info->dwSignature != 0xFEEF04BD) {
        return std::nullopt;
    }

    return std::to_wstring(HIWORD(info->dwFileVersionMS)) + L"."
        + std::to_wstring(LOWORD(info->dwFileVersionMS)) + L"."
        + std::to_wstring(HIWORD(info->dwFileVersionLS)) + L"."
        + std::to_wstring(LOWORD(info->dwFileVersionLS));
}

std::string toLowerAscii(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return text;
}

bool isSha256(const std::string &value) {
    if (value.size() != 64)
        return false;
    for (unsigned char c : value) {
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
              || (c >= 'A' && c <= 'F'))) {
            return false;
        }
    }
    return true;
}

bool sha256File(const fs::path &path, std::string &digest, std::wstring &error) {
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    DWORD objectLength = 0;
    DWORD received = 0;
    DWORD hashLength = 0;
    std::vector<BYTE> hashObject;
    std::vector<BYTE> hashBytes;
    HANDLE file = INVALID_HANDLE_VALUE;
    bool okay = false;

    NTSTATUS status = BCryptOpenAlgorithmProvider(
        &algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
    if (!BCRYPT_SUCCESS(status)) {
        error = L"Could not initialize SHA-256 validation.";
        goto cleanup;
    }
    status = BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                               reinterpret_cast<PUCHAR>(&objectLength),
                               sizeof(objectLength), &received, 0);
    if (!BCRYPT_SUCCESS(status)) {
        error = L"Could not initialize the SHA-256 workspace.";
        goto cleanup;
    }
    status = BCryptGetProperty(algorithm, BCRYPT_HASH_LENGTH,
                               reinterpret_cast<PUCHAR>(&hashLength),
                               sizeof(hashLength), &received, 0);
    if (!BCRYPT_SUCCESS(status) || hashLength != 32) {
        error = L"Could not determine SHA-256 output size.";
        goto cleanup;
    }
    hashObject.resize(objectLength);
    hashBytes.resize(hashLength);
    status = BCryptCreateHash(algorithm, &hash, hashObject.data(), objectLength,
                              nullptr, 0, 0);
    if (!BCRYPT_SUCCESS(status)) {
        error = L"Could not create SHA-256 hash context.";
        goto cleanup;
    }

    file = CreateFileW(path.c_str(), GENERIC_READ,
                       FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr,
                       OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = systemErrorText(L"Could not open file for SHA-256 validation");
        goto cleanup;
    }

    {
        BYTE buffer[64 * 1024];
        for (;;) {
            DWORD bytesRead = 0;
            if (!ReadFile(file, buffer, sizeof(buffer), &bytesRead, nullptr)) {
                error = systemErrorText(L"Could not read file for SHA-256 validation");
                goto cleanup;
            }
            if (bytesRead == 0)
                break;
            status = BCryptHashData(hash, buffer, bytesRead, 0);
            if (!BCRYPT_SUCCESS(status)) {
                error = L"SHA-256 processing failed.";
                goto cleanup;
            }
        }
    }

    status = BCryptFinishHash(hash, hashBytes.data(), hashLength, 0);
    if (!BCRYPT_SUCCESS(status)) {
        error = L"Could not finish SHA-256 validation.";
        goto cleanup;
    }

    {
        static constexpr char hex[] = "0123456789abcdef";
        digest.clear();
        digest.reserve(hashBytes.size() * 2);
        for (BYTE value : hashBytes) {
            digest.push_back(hex[value >> 4]);
            digest.push_back(hex[value & 0x0F]);
        }
    }
    okay = true;

cleanup:
    if (file != INVALID_HANDLE_VALUE)
        CloseHandle(file);
    if (hash)
        BCryptDestroyHash(hash);
    if (algorithm)
        BCryptCloseAlgorithmProvider(algorithm, 0);
    return okay;
}

struct HttpHandles {
    HINTERNET session = nullptr;
    HINTERNET connection = nullptr;
    HINTERNET request = nullptr;

    ~HttpHandles() {
        if (request) WinHttpCloseHandle(request);
        if (connection) WinHttpCloseHandle(connection);
        if (session) WinHttpCloseHandle(session);
    }
};

bool openSecureGet(const std::wstring &url, HttpHandles &handles,
                   std::wstring &error) {
    URL_COMPONENTS components{};
    components.dwStructSize = sizeof(components);
    components.dwSchemeLength = static_cast<DWORD>(-1);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(url.c_str(), 0, 0, &components)
        || components.nScheme != INTERNET_SCHEME_HTTPS
        || components.dwHostNameLength == 0) {
        error = L"Only valid HTTPS URLs are accepted.";
        return false;
    }

    const std::wstring host(components.lpszHostName, components.dwHostNameLength);
    std::wstring path;
    if (components.dwUrlPathLength > 0)
        path.assign(components.lpszUrlPath, components.dwUrlPathLength);
    if (path.empty())
        path = L"/";
    if (components.dwExtraInfoLength > 0) {
        std::wstring extra(components.lpszExtraInfo, components.dwExtraInfoLength);
        const size_t fragment = extra.find(L'#');
        if (fragment != std::wstring::npos)
            extra.resize(fragment);
        path += extra;
    }

    const std::wstring agent = L"ArgonBootstrap/" + widenUtf8(ARGON_BOOTSTRAP_VERSION);
    handles.session = WinHttpOpen(agent.c_str(),
                                  WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                  WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!handles.session) {
        error = systemErrorText(L"Could not start secure HTTP session");
        return false;
    }
    WinHttpSetTimeouts(handles.session, 5000, 8000, 8000, 8000);

    handles.connection = WinHttpConnect(handles.session, host.c_str(),
                                         components.nPort, 0);
    if (!handles.connection) {
        error = systemErrorText(L"Could not connect to the metadata host");
        return false;
    }
    handles.request = WinHttpOpenRequest(
        handles.connection, L"GET", path.c_str(), nullptr, WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!handles.request) {
        error = systemErrorText(L"Could not open secure download request");
        return false;
    }

#if defined(WINHTTP_OPTION_REDIRECT_POLICY) && defined(WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP)
    DWORD redirectPolicy = WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP;
    WinHttpSetOption(handles.request, WINHTTP_OPTION_REDIRECT_POLICY,
                     &redirectPolicy, sizeof(redirectPolicy));
#endif
    const wchar_t *headers = L"Accept: application/json, application/octet-stream\r\nCache-Control: no-cache, no-store, max-age=0\r\nPragma: no-cache\r\n";
    if (!WinHttpSendRequest(handles.request, headers, static_cast<DWORD>(-1),
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0)
        || !WinHttpReceiveResponse(handles.request, nullptr)) {
        error = systemErrorText(L"Secure request failed");
        return false;
    }

    DWORD statusCode = 0;
    DWORD statusSize = sizeof(statusCode);
    if (!WinHttpQueryHeaders(handles.request,
                             WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &statusCode,
                             &statusSize, WINHTTP_NO_HEADER_INDEX)) {
        error = systemErrorText(L"Could not read HTTP response status");
        return false;
    }
    if (statusCode < 200 || statusCode >= 300) {
        error = L"Server returned HTTP " + std::to_wstring(statusCode) + L".";
        return false;
    }
    return true;
}

std::wstring appendCacheBuster(const std::wstring &url) {
    return url + (url.find(L'?') == std::wstring::npos ? L"?" : L"&")
        + L"argon_refresh=" + std::to_wstring(GetTickCount64());
}

bool httpGetText(const std::wstring &url, std::string &body,
                 std::wstring &error) {
    HttpHandles handles;
    if (!openSecureGet(appendCacheBuster(url), handles, error))
        return false;

    body.clear();
    char buffer[8192];
    for (;;) {
        DWORD bytesRead = 0;
        if (!WinHttpReadData(handles.request, buffer, sizeof(buffer), &bytesRead)) {
            error = systemErrorText(L"Could not read the HTTP response");
            return false;
        }
        if (bytesRead == 0)
            break;
        if (body.size() + bytesRead > kMaximumMetadataBytes) {
            error = L"Version metadata exceeds the permitted 1 MiB limit.";
            return false;
        }
        body.append(buffer, bytesRead);
    }
    return true;
}

bool downloadFile(const std::wstring &url, const fs::path &destination,
                  unsigned long long expectedSize, std::wstring &error) {
    HttpHandles handles;
    if (!openSecureGet(url, handles, error))
        return false;
    if (!ensureDirectory(destination.parent_path(), error))
        return false;

    HANDLE file = CreateFileW(destination.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        error = systemErrorText(L"Could not create updater download staging file");
        return false;
    }

    unsigned long long total = 0;
    bool okay = true;
    BYTE buffer[64 * 1024];
    for (;;) {
        DWORD bytesRead = 0;
        if (!WinHttpReadData(handles.request, buffer, sizeof(buffer), &bytesRead)) {
            error = systemErrorText(L"Updater download was interrupted");
            okay = false;
            break;
        }
        if (bytesRead == 0)
            break;
        total += bytesRead;
        if (total > kMaximumUpdaterBytes || total > expectedSize) {
            error = L"Updater download exceeded the declared package size.";
            okay = false;
            break;
        }
        DWORD offset = 0;
        while (offset < bytesRead) {
            DWORD bytesWritten = 0;
            if (!WriteFile(file, buffer + offset, bytesRead - offset,
                           &bytesWritten, nullptr) || bytesWritten == 0) {
                error = systemErrorText(L"Could not write updater download");
                okay = false;
                break;
            }
            offset += bytesWritten;
        }
        if (!okay)
            break;
    }

    if (okay && total != expectedSize) {
        error = L"Updater download is incomplete: received "
            + std::to_wstring(total) + L" of "
            + std::to_wstring(expectedSize) + L" bytes.";
        okay = false;
    }
    if (okay && !FlushFileBuffers(file)) {
        error = systemErrorText(L"Could not flush downloaded updater");
        okay = false;
    }
    CloseHandle(file);

    if (!okay) {
        DeleteFileW(destination.c_str());
        return false;
    }
    return true;
}

bool validHttpsUrl(const std::string &url) {
    if (url.empty() || url.size() > 2048)
        return false;
    const std::wstring wide = widenUtf8(url);
    if (wide.empty())
        return false;
    URL_COMPONENTS components{};
    components.dwStructSize = sizeof(components);
    components.dwSchemeLength = static_cast<DWORD>(-1);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    return WinHttpCrackUrl(wide.c_str(), 0, 0, &components)
        && components.nScheme == INTERNET_SCHEME_HTTPS
        && components.dwHostNameLength > 0;
}

bool getSchema(const std::map<std::string, std::string> &fields,
               std::wstring &error) {
    const auto schema = field(fields, "schemaVersion");
    const auto product = field(fields, "product");
    const auto channel = field(fields, "channel");
    if (!schema || *schema != "1" || !product || *product != "Argon"
        || !channel || *channel != "stable") {
        error = L"Metadata must use schemaVersion 1, product Argon, and the stable channel.";
        return false;
    }
    return true;
}

std::optional<fs::path> bootstrapMetadataCachePath() {
    const DWORD required = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
    if (required < 2 || required > 32767)
        return std::nullopt;

    std::wstring localAppData(required, L'\0');
    const DWORD length = GetEnvironmentVariableW(
        L"LOCALAPPDATA", localAppData.data(), required);
    if (length == 0 || length >= required)
        return std::nullopt;
    localAppData.resize(length);
    return fs::path(localAppData) / L"Argon" / L"Bootstrap"
        / L"bootstrap-latest.json";
}

bool loadCachedBootstrapMetadata(std::string &text, std::wstring &error) {
    const auto path = bootstrapMetadataCachePath();
    if (!path) {
        error = L"LOCALAPPDATA is unavailable; no metadata cache path can be resolved.";
        return false;
    }
    return readFileText(*path, text, static_cast<size_t>(kMaximumMetadataBytes), error);
}

bool cacheBootstrapMetadata(const std::string &text, std::wstring &error) {
    const auto path = bootstrapMetadataCachePath();
    if (!path) {
        error = L"LOCALAPPDATA is unavailable; release metadata could not be cached.";
        return false;
    }
    return writeTextAtomically(*path, text, error);
}

bool parseBootstrapMetadata(const std::string &text,
                            std::map<std::string, std::string> &manifest,
                            std::string &latestBootstrap,
                            std::wstring &error) {
    if (!parseJson(text, manifest, error) || !getSchema(manifest, error))
        return false;

    const auto version = field(manifest, "bootstrapVersion");
    std::array<unsigned long long, 4> parsed{};
    if (!version || !parseVersion(*version, parsed)) {
        error = L"Metadata does not contain a valid four-part bootstrapVersion.";
        return false;
    }
    latestBootstrap = *version;
    return true;
}

std::wstring describeBootstrapVersion(const std::string &installed,
                                      const std::string &latest,
                                      bool offline) {
    const auto comparisonResult = compareVersions(installed, latest);
    if (!comparisonResult) {
        return offline
            ? L"Offline — cached Bootstrap version could not be compared safely; reconnect to verify."
            : L"Bootstrap version comparison failed; installed version or live metadata is invalid.";
    }
    const int comparison = *comparisonResult;
    if (offline) {
        if (comparison < 0) {
            return L"Offline — cached metadata says Bootstrap v"
                + widenUtf8(latest) + L" is newer than installed v"
                + widenUtf8(installed) + L"; reconnect to verify.";
        }
        if (comparison > 0) {
            return L"Offline — installed Bootstrap v" + widenUtf8(installed)
                + L" is newer than last-known stable v" + widenUtf8(latest)
                + L"; reconnect to verify.";
        }
        return L"Offline — installed v" + widenUtf8(installed)
            + L" matches last-known stable v" + widenUtf8(latest)
            + L"; live status is unverified.";
    }

    if (comparison < 0) {
        return L"A newer Bootstrap is available (v" + widenUtf8(latest)
            + L"; installed v" + widenUtf8(installed) + L").";
    }
    if (comparison > 0) {
        return L"Installed Bootstrap v" + widenUtf8(installed)
            + L" is newer than configured stable v" + widenUtf8(latest) + L".";
    }
    return L"Bootstrap is up to date (v" + widenUtf8(installed) + L").";
}

bool validHashMatches(const fs::path &path, const std::string &expected,
                      std::wstring &error) {
    std::string actual;
    if (!sha256File(path, actual, error))
        return false;
    if (toLowerAscii(actual) != toLowerAscii(expected)) {
        error = L"SHA-256 checksum mismatch. The updater file was not installed.";
        return false;
    }
    return true;
}

bool isSimpleFileName(const std::string &name) {
    if (name.empty() || name == "." || name == "..")
        return false;
    return name.find('/') == std::string::npos
        && name.find('\\') == std::string::npos
        && name.find(':') == std::string::npos;
}

std::map<std::string, std::string> parseKeyValueLines(const std::string &text) {
    std::map<std::string, std::string> values;
    size_t position = 0;
    while (position < text.size()) {
        size_t end = text.find_first_of("\r\n", position);
        if (end == std::string::npos)
            end = text.size();
        const std::string line = text.substr(position, end - position);
        const size_t equals = line.find('=');
        if (equals != std::string::npos && equals > 0)
            values[line.substr(0, equals)] = line.substr(equals + 1);
        position = end + 1;
    }
    return values;
}

bool restoreFromBackup(const Paths &paths, const fs::path &backup,
                       const std::string &expectedOriginalHash,
                       std::wstring &error) {
    if (!fileExists(backup)) {
        error = L"The safety backup is missing. The pending recovery record has been preserved.";
        return false;
    }
    if (!validHashMatches(backup, expectedOriginalHash, error)) {
        error = L"The safety backup failed its checksum check. No files were replaced.";
        return false;
    }

    fs::path rollbackCopy = paths.updaterDirectory / L"ArgonUpdater.exe.rollback";
    if (!deleteFileIfPresent(rollbackCopy, error))
        return false;
    if (!CopyFileW(backup.c_str(), rollbackCopy.c_str(), TRUE)) {
        error = systemErrorText(L"Could not prepare updater rollback copy");
        return false;
    }

    bool replaced = false;
    if (fileExists(paths.updaterExecutable)) {
        replaced = ReplaceFileW(paths.updaterExecutable.c_str(), rollbackCopy.c_str(),
                                nullptr, REPLACEFILE_IGNORE_MERGE_ERRORS,
                                nullptr, nullptr) != FALSE;
    } else {
        replaced = MoveFileExW(rollbackCopy.c_str(), paths.updaterExecutable.c_str(),
                               MOVEFILE_WRITE_THROUGH) != FALSE;
    }
    if (!replaced) {
        error = systemErrorText(L"Could not restore original updater");
        DeleteFileW(rollbackCopy.c_str());
        return false;
    }
    if (!validHashMatches(paths.updaterExecutable, expectedOriginalHash, error)) {
        error = L"Restored updater did not match its safety backup. The original backup remains available.";
        return false;
    }
    return true;
}

bool recoverPendingTransaction(const Paths &paths, std::wstring &recoveryNote,
                               std::wstring &error) {
    if (!fileExists(paths.journalFile))
        return true;

    std::string journalText;
    if (!readFileText(paths.journalFile, journalText, 16 * 1024, error))
        return false;
    const auto journal = parseKeyValueLines(journalText);
    const auto hadExistingField = field(journal, "hadExisting");
    const auto backupFileField = field(journal, "backupFile");
    const auto originalHashField = field(journal, "originalSha256");
    const auto expectedHashField = field(journal, "expectedSha256");
    if (!hadExistingField || !backupFileField || !originalHashField
        || !expectedHashField || (*hadExistingField != "0" && *hadExistingField != "1")
        || !isSha256(*expectedHashField)
        || (*hadExistingField == "1"
            && (!isSimpleFileName(*backupFileField) || !isSha256(*originalHashField)))) {
        error = L"The pending updater transaction record is invalid. No files were changed.";
        return false;
    }

    std::string actualTargetHash;
    std::wstring hashError;
    const bool targetExists = fileExists(paths.updaterExecutable);
    const bool targetMatchesExpected = targetExists
        && sha256File(paths.updaterExecutable, actualTargetHash, hashError)
        && toLowerAscii(actualTargetHash) == toLowerAscii(*expectedHashField);

    if (targetMatchesExpected) {
        if (*hadExistingField == "1") {
            const fs::path backup = paths.backupsDirectory / widenUtf8(*backupFileField);
            if (!fileExists(backup)) {
                error = L"The new updater is present, but its safety backup is missing. Recovery has been paused.";
                return false;
            }
        }
        if (!DeleteFileW(paths.journalFile.c_str())
            && GetLastError() != ERROR_FILE_NOT_FOUND) {
            error = systemErrorText(L"Could not clear the verified updater transaction record");
            return false;
        }
        recoveryNote = L"A previously interrupted updater transaction was verified and recovered.";
        return true;
    }

    if (*hadExistingField == "1") {
        const fs::path backup = paths.backupsDirectory / widenUtf8(*backupFileField);
        if (!restoreFromBackup(paths, backup, *originalHashField, error))
            return false;
        recoveryNote = L"A previously interrupted updater transaction was rolled back to its safety backup.";
    } else if (targetExists) {
        if (!DeleteFileW(paths.updaterExecutable.c_str())) {
            error = systemErrorText(L"Could not remove incomplete first-install updater");
            return false;
        }
        recoveryNote = L"A failed first-time updater installation was removed.";
    } else {
        recoveryNote = L"A pending updater transaction was cleared; no updater had been installed.";
    }

    if (!DeleteFileW(paths.journalFile.c_str())
        && GetLastError() != ERROR_FILE_NOT_FOUND) {
        error = systemErrorText(L"Could not clear the recovered updater transaction record");
        return false;
    }
    return true;
}

std::wstring timestampForBackup() {
    SYSTEMTIME now{};
    GetLocalTime(&now);
    wchar_t buffer[64]{};
    std::swprintf(buffer, 64, L"%04u%02u%02u-%02u%02u%02u-%03u",
               now.wYear, now.wMonth, now.wDay, now.wHour,
               now.wMinute, now.wSecond, now.wMilliseconds);
    return buffer;
}

bool performSafeReplacement(const Paths &paths, const fs::path &downloadFilePath,
                            const std::string &version, const std::string &expectedHash,
                            std::wstring &details, std::wstring &error) {
    const bool hadExisting = fileExists(paths.updaterExecutable);
    std::string originalHash;
    fs::path backupPath;
    std::string backupName = "-";

    if (hadExisting) {
        if (!sha256File(paths.updaterExecutable, originalHash, error))
            return false;
        const auto oldVersion = readPeVersion(paths.updaterExecutable);
        const std::wstring oldVersionText = oldVersion.value_or(L"unknown");
        backupName = "ArgonUpdater-" + narrowUtf8(timestampForBackup()) + "-"
            + narrowUtf8(oldVersionText) + ".exe";
        backupPath = paths.backupsDirectory / widenUtf8(backupName);
        if (!CopyFileW(paths.updaterExecutable.c_str(), backupPath.c_str(), TRUE)) {
            error = systemErrorText(L"Could not create the safety backup");
            return false;
        }
        if (!validHashMatches(backupPath, originalHash, error)) {
            error = L"The safety backup did not match the original updater. The install was cancelled.";
            return false;
        }
    }

    fs::path replacementPath = paths.updaterDirectory / L"ArgonUpdater.exe.new";
    if (!deleteFileIfPresent(replacementPath, error))
        return false;
    if (!CopyFileW(downloadFilePath.c_str(), replacementPath.c_str(), TRUE)) {
        error = systemErrorText(L"Could not prepare updater replacement file");
        return false;
    }
    if (!validHashMatches(replacementPath, expectedHash, error)) {
        DeleteFileW(replacementPath.c_str());
        return false;
    }

    const std::string journal =
        "schemaVersion=1\r\n"
        "hadExisting=" + std::string(hadExisting ? "1" : "0") + "\r\n"
        "backupFile=" + backupName + "\r\n"
        "originalSha256=" + (hadExisting ? originalHash : "-") + "\r\n"
        "expectedSha256=" + expectedHash + "\r\n"
        "expectedVersion=" + version + "\r\n";
    if (!writeTextAtomically(paths.journalFile, journal, error)) {
        DeleteFileW(replacementPath.c_str());
        return false;
    }

    bool replaced = false;
    if (hadExisting) {
        replaced = ReplaceFileW(paths.updaterExecutable.c_str(), replacementPath.c_str(),
                                nullptr, REPLACEFILE_IGNORE_MERGE_ERRORS,
                                nullptr, nullptr) != FALSE;
    } else {
        replaced = MoveFileExW(replacementPath.c_str(), paths.updaterExecutable.c_str(),
                               MOVEFILE_WRITE_THROUGH) != FALSE;
    }

    if (!replaced) {
        error = systemErrorText(L"Could not atomically replace ArgonUpdater.exe");
        std::wstring recoveryError;
        std::wstring ignoredNote;
        if (!recoverPendingTransaction(paths, ignoredNote, recoveryError))
            error += L" Recovery also failed: " + recoveryError;
        return false;
    }

    std::wstring verificationError;
    const auto installedVersion = readPeVersion(paths.updaterExecutable);
    const bool verified = validHashMatches(paths.updaterExecutable, expectedHash,
                                           verificationError)
        && installedVersion
        && narrowUtf8(*installedVersion) == version;
    if (!verified) {
        error = L"The replacement updater failed its post-install validation.";
        if (!verificationError.empty())
            error += L" " + verificationError;
        std::wstring recoveryError;
        std::wstring ignoredNote;
        if (!recoverPendingTransaction(paths, ignoredNote, recoveryError)) {
            error += L" Rollback is still pending: " + recoveryError;
        } else {
            error += L" The previous updater was restored.";
        }
        return false;
    }

    if (!DeleteFileW(paths.journalFile.c_str())) {
        error = systemErrorText(L"Updater was verified, but the transaction record could not be cleared");
        return false;
    }

    std::wstring cleanupError;
    deleteFileIfPresent(downloadFilePath, cleanupError);
    details = L"Updater v" + widenUtf8(version) + L" was installed and verified. ";
    if (hadExisting) {
        details += L"The original updater was preserved at:\r\n"
            + backupPath.wstring();
    } else {
        details += L"This was the first install, so there was no previous updater to back up.";
    }
    return true;
}

CheckResult runStatusCheck() {
    CheckResult result;
    const std::string localBootstrapVersion = ARGON_BOOTSTRAP_VERSION;
    result.bootstrapStatus = L"Checking Bootstrap v"
        + widenUtf8(localBootstrapVersion) + L"...";
    result.updaterStatus = L"Checking installed updater...";
    std::array<unsigned long long, 4> localBootstrapParts{};
    if (!parseVersion(localBootstrapVersion, localBootstrapParts)) {
        result.bootstrapStatus = L"Bootstrap's built-in version is invalid.";
        result.updaterStatus = L"Updater status unavailable.";
        result.details = L"The build's ARGON_BOOTSTRAP_VERSION must contain exactly four numeric components. No files were changed.";
        return result;
    }

    std::wstring pathError;
    const auto pathsOption = resolvePaths(pathError);
    if (!pathsOption) {
        result.bootstrapStatus = L"Bootstrap could not resolve its install directory.";
        result.updaterStatus = L"Updater status unavailable.";
        result.details = pathError;
        return result;
    }
    const Paths paths = *pathsOption;

    for (const fs::path &directory : {paths.updaterDirectory, paths.downloadsDirectory,
                                      paths.stagingDirectory, paths.backupsDirectory}) {
        if (!ensureDirectory(directory, pathError)) {
            result.bootstrapStatus = L"Bootstrap safety check could not start.";
            result.updaterStatus = L"No updater changes were made.";
            result.details = pathError;
            return result;
        }
    }

    std::wstring recoveryNote;
    std::wstring recoveryError;
    if (!recoverPendingTransaction(paths, recoveryNote, recoveryError)) {
        result.bootstrapStatus = L"Bootstrap paused for safety.";
        result.updaterStatus = L"Pending updater recovery requires attention.";
        result.details = recoveryError + L"\r\nNo new update was attempted.";
        return result;
    }

    std::string manifestText;
    std::wstring networkError;
    if (!httpGetText(widenUtf8(ARGON_BOOTSTRAP_LATEST_URL), manifestText, networkError)) {
        std::string cachedText;
        std::map<std::string, std::string> cachedManifest;
        std::string cachedBootstrap;
        std::wstring cacheError;
        if (loadCachedBootstrapMetadata(cachedText, cacheError)
            && parseBootstrapMetadata(cachedText, cachedManifest,
                                      cachedBootstrap, cacheError)) {
            result.bootstrapStatus = describeBootstrapVersion(
                localBootstrapVersion, cachedBootstrap, true);

            const auto cachedUpdater = field(cachedManifest, "updaterVersion");
            std::array<unsigned long long, 4> parsedCachedUpdater{};
            const auto localUpdaterVersion = readPeVersion(paths.updaterExecutable);
            if (cachedUpdater && parseVersion(*cachedUpdater, parsedCachedUpdater)) {
                if (!localUpdaterVersion) {
                    result.updaterStatus = L"Offline — updater is not installed or has no version resource; last-known stable is v"
                        + widenUtf8(*cachedUpdater) + L".";
                } else {
                    const std::string installedUpdater = narrowUtf8(*localUpdaterVersion);
                    const auto comparison = compareVersions(installedUpdater, *cachedUpdater);
                    if (!comparison) {
                        result.updaterStatus = L"Offline — updater versions could not be compared safely.";
                    } else if (*comparison < 0) {
                        result.updaterStatus = L"Offline — a newer updater may be available (last-known v"
                            + widenUtf8(*cachedUpdater) + L"; installed v"
                            + *localUpdaterVersion + L").";
                    } else if (*comparison > 0) {
                        result.updaterStatus = L"Offline — installed updater v"
                            + *localUpdaterVersion + L" is newer than last-known stable v"
                            + widenUtf8(*cachedUpdater) + L".";
                    } else {
                        result.updaterStatus = L"Offline — installed updater v"
                            + *localUpdaterVersion + L" matches last-known stable; live status is unverified.";
                    }
                }
            } else {
                result.updaterStatus = localUpdaterVersion
                    ? L"Offline — installed updater: v" + *localUpdaterVersion
                    : L"Offline — updater is not installed or has no version resource.";
            }
            result.details = networkError
                + L"\r\nUsing previously cached release metadata as a hint only. "
                  L"It may be stale; reconnect for a live check. No files were changed.";
            if (!recoveryNote.empty())
                result.details += L"\r\n" + recoveryNote;
            return result;
        }

        result.bootstrapStatus = L"Offline — latest Bootstrap version is unknown (installed v"
            + widenUtf8(localBootstrapVersion) + L").";
        const auto localUpdaterVersion = readPeVersion(paths.updaterExecutable);
        result.updaterStatus = localUpdaterVersion
            ? L"Offline — installed updater: v" + *localUpdaterVersion
            : L"Offline — updater is not installed or has no version resource.";
        result.details = networkError
            + L"\r\nNo usable cached metadata exists, so latest versions cannot be confirmed. "
              L"No files were changed.";
        if (!cacheError.empty())
            result.details += L"\r\nCache: " + cacheError;
        if (!recoveryNote.empty())
            result.details += L"\r\n" + recoveryNote;
        return result;
    }

    std::map<std::string, std::string> manifest;
    std::wstring jsonError;
    std::string latestBootstrapVersion;
    if (!parseBootstrapMetadata(manifestText, manifest, latestBootstrapVersion, jsonError)) {
        result.bootstrapStatus = L"Release metadata is invalid; the latest Bootstrap version cannot be trusted.";
        result.updaterStatus = L"No updater changes were made.";
        result.details = L"bootstrap-latest.json could not be validated: " + jsonError
            + L"\r\nNo files were changed.";
        return result;
    }

    result.bootstrapStatus = describeBootstrapVersion(
        localBootstrapVersion, latestBootstrapVersion, false);

    std::wstring cacheWriteError;
    const bool metadataCached = cacheBootstrapMetadata(manifestText, cacheWriteError);

    const auto latestUpdater = field(manifest, "updaterVersion");
    const auto directoryUrl = field(manifest, "directoryUrl");
    std::array<unsigned long long, 4> parsedVersion{};
    if (!latestUpdater || !parseVersion(*latestUpdater, parsedVersion)
        || !directoryUrl || !validHttpsUrl(*directoryUrl)) {
        result.updaterStatus = L"No updater changes were made.";
        result.details = L"Bootstrap version status was checked live, but updater metadata is incomplete or invalid. "
            L"bootstrap-latest.json must contain a valid updaterVersion and HTTPS directoryUrl.";
        if (!cacheWriteError.empty())
            result.details += L"\r\nMetadata cache: " + cacheWriteError;
        return result;
    }
    if (!metadataCached && !cacheWriteError.empty())
        result.details = L"Live metadata was verified, but could not be cached: " + cacheWriteError + L"\r\n";

    const auto currentUpdater = readPeVersion(paths.updaterExecutable);
    if (currentUpdater) {
        const std::string localUpdaterVersion = narrowUtf8(*currentUpdater);
        const auto updaterComparisonResult = compareVersions(localUpdaterVersion, *latestUpdater);
        if (!updaterComparisonResult) {
            result.updaterStatus = L"Installed updater version could not be compared safely.";
            result.details += L"No updater changes were made because its version metadata is invalid.";
            return result;
        }
        const int updaterComparison = *updaterComparisonResult;
        if (updaterComparison == 0) {
            result.updaterStatus = L"Updater is up to date (v" + *currentUpdater + L").";
            result.details += recoveryNote.empty()
                ? L"Release metadata was verified over HTTPS. No files needed changing."
                : recoveryNote + L"\r\nRelease metadata was verified over HTTPS.";
            return result;
        }
        if (updaterComparison > 0) {
            result.updaterStatus = L"Installed updater v" + *currentUpdater
                + L" is newer than stable v" + widenUtf8(*latestUpdater) + L".";
            result.details += L"No downgrade was attempted. Release metadata was verified over HTTPS.";
            if (!recoveryNote.empty())
                result.details += L"\r\n" + recoveryNote;
            return result;
        }
        result.updaterStatus = L"Updater update available: v"
            + widenUtf8(*latestUpdater) + L" (installed v" + *currentUpdater + L").";
    } else if (fileExists(paths.updaterExecutable)) {
        result.updaterStatus = L"Updater update available: local version could not be read; latest is v"
            + widenUtf8(*latestUpdater) + L".";
    } else {
        result.updaterStatus = L"Updater is not installed; latest version is v"
            + widenUtf8(*latestUpdater) + L".";
    }

    std::string directoryText;
    if (!httpGetText(widenUtf8(*directoryUrl), directoryText, networkError)) {
        result.details = L"An updater update is required, but directory.json could not be retrieved. "
            L"No files were changed.\r\n" + networkError;
        if (!recoveryNote.empty())
            result.details += L"\r\n" + recoveryNote;
        return result;
    }

    std::map<std::string, std::string> directory;
    if (!parseJson(directoryText, directory, jsonError) || !getSchema(directory, jsonError)) {
        result.details = L"directory.json could not be validated: " + jsonError
            + L"\r\nNo files were changed.";
        return result;
    }

    const auto directoryUpdater = field(directory, "updaterVersion");
    const auto packageUrl = field(directory, "packageUrl");
    const auto expectedHash = field(directory, "sha256");
    const auto expectedSizeText = field(directory, "sizeBytes");
    const auto minimumBootstrap = field(directory, "minimumBootstrapVersion");
    if (!directoryUpdater || *directoryUpdater != *latestUpdater
        || !minimumBootstrap || !parseVersion(*minimumBootstrap, parsedVersion)) {
        result.details = L"directory.json does not match the requested updater version or has invalid minimumBootstrapVersion. No files were changed.";
        return result;
    }
    const auto minimumComparison = compareVersions(localBootstrapVersion, *minimumBootstrap);
    if (!minimumComparison) {
        result.details = L"Bootstrap and minimumBootstrapVersion could not be compared safely. No files were changed.";
        return result;
    }
    if (*minimumComparison < 0) {
        result.details = L"This updater package requires Bootstrap v"
            + widenUtf8(*minimumBootstrap) + L" or newer. The installed Bootstrap cannot safely install it.";
        return result;
    }

    if (!packageUrl || packageUrl->empty() || !expectedHash
        || !isSha256(*expectedHash) || !expectedSizeText) {
        result.details = L"directory.json lists updater v" + widenUtf8(*latestUpdater)
            + L", but a valid packageUrl, SHA-256 checksum, and sizeBytes have not been published yet. "
              L"No files were changed.";
        if (!recoveryNote.empty())
            result.details += L"\r\n" + recoveryNote;
        return result;
    }
    if (!validHttpsUrl(*packageUrl)) {
        result.details = L"directory.json packageUrl must use HTTPS. No files were changed.";
        return result;
    }

    unsigned long long expectedSize = 0;
    for (const char digit : *expectedSizeText) {
        if (digit < '0' || digit > '9'
            || expectedSize > (kMaximumUpdaterBytes / 10)) {
            result.details = L"directory.json sizeBytes is invalid. No files were changed.";
            return result;
        }
        expectedSize = expectedSize * 10 + static_cast<unsigned long long>(digit - '0');
    }
    if (expectedSize == 0 || expectedSize > kMaximumUpdaterBytes) {
        result.details = L"directory.json sizeBytes must be between 1 byte and 512 MiB. No files were changed.";
        return result;
    }

    const fs::path download = paths.downloadsDirectory
        / (L"ArgonUpdater-" + widenUtf8(*latestUpdater) + L".download.tmp");
    std::wstring temporaryError;
    if (!deleteFileIfPresent(download, temporaryError)) {
        result.details = temporaryError + L"\r\nNo files were changed.";
        return result;
    }
    if (!downloadFile(widenUtf8(*packageUrl), download, expectedSize, networkError)) {
        result.details = L"Updater download failed. The installed updater was left untouched.\r\n"
            + networkError;
        if (!recoveryNote.empty())
            result.details += L"\r\n" + recoveryNote;
        return result;
    }

    std::string actualHash;
    if (!sha256File(download, actualHash, temporaryError)
        || toLowerAscii(actualHash) != toLowerAscii(*expectedHash)) {
        DeleteFileW(download.c_str());
        result.details = L"Downloaded updater failed SHA-256 validation. The installed updater was left untouched.";
        if (!temporaryError.empty())
            result.details += L"\r\n" + temporaryError;
        return result;
    }

    const auto packageVersion = readPeVersion(download);
    if (!packageVersion || narrowUtf8(*packageVersion) != *latestUpdater) {
        DeleteFileW(download.c_str());
        result.details = L"Downloaded file's embedded Windows version does not match directory.json. The installed updater was left untouched.";
        return result;
    }

    if (!performSafeReplacement(paths, download, *latestUpdater, *expectedHash,
                                result.details, networkError)) {
        result.details = networkError;
        return result;
    }

    result.updaterStatus = L"Updater is up to date (v" + widenUtf8(*latestUpdater) + L").";
    result.details += L"Release metadata was verified over HTTPS and updater integrity checks passed. ";
    if (!recoveryNote.empty())
        result.details += L"\r\n" + recoveryNote;
    return result;
}

void setControlText(HWND control, const std::wstring &value);

void setControlText(HWND control, const std::wstring &value) {
    if (control)
        SetWindowTextW(control, value.c_str());
}

void setControlFont(HWND control, HFONT font) {
    if (control && font)
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
}

void startStatusCheck(HWND window) {
    setControlText(g_bootstrapStatus, L"Checking Bootstrap metadata...");
    setControlText(g_updaterStatus, L"Checking installed updater...");
    setControlText(g_details, L"Contacting the stable metadata endpoint over HTTPS. Existing updater files remain untouched until a complete package passes validation.");

    HANDLE thread = CreateThread(nullptr, 0,
        [](LPVOID parameter) -> DWORD {
            HWND target = static_cast<HWND>(parameter);
            auto result = new CheckResult(runStatusCheck());
            if (!PostMessageW(target, kCheckCompleteMessage, 0,
                              reinterpret_cast<LPARAM>(result))) {
                delete result;
            }
            return 0;
        }, window, 0, nullptr);
    if (thread)
        CloseHandle(thread);
    else {
        setControlText(g_bootstrapStatus, L"Could not start the status check.");
        setControlText(g_updaterStatus, L"No updater changes were made.");
        setControlText(g_details, systemErrorText(L"CreateThread failed"));
    }
}

LRESULT CALLBACK windowProcedure(HWND window, UINT message,
                                 WPARAM wParam, LPARAM lParam) {
    switch (message) {
    case WM_CREATE: {
        g_headingFont = CreateFontW(-24, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE,
                                    FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                                    CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                    DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        HFONT regularFont = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
        HWND heading = CreateWindowExW(0, L"STATIC", L"Argon Bootstrap",
            WS_CHILD | WS_VISIBLE, 28, 22, 540, 36, window, nullptr,
            GetModuleHandleW(nullptr), nullptr);
        setControlFont(heading, g_headingFont);
        HWND subtitle = CreateWindowExW(0, L"STATIC",
            L"Release metadata and updater integrity status",
            WS_CHILD | WS_VISIBLE, 30, 57, 540, 22, window, nullptr,
            GetModuleHandleW(nullptr), nullptr);
        setControlFont(subtitle, regularFont);

        g_bootstrapStatus = CreateWindowExW(0, L"STATIC", L"Starting...",
            WS_CHILD | WS_VISIBLE, 30, 96, 540, 25, window, nullptr,
            GetModuleHandleW(nullptr), nullptr);
        g_updaterStatus = CreateWindowExW(0, L"STATIC", L"Starting...",
            WS_CHILD | WS_VISIBLE, 30, 128, 540, 25, window, nullptr,
            GetModuleHandleW(nullptr), nullptr);
        g_details = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL
                | ES_READONLY | WS_VSCROLL,
            30, 165, 540, 105, window, nullptr, GetModuleHandleW(nullptr), nullptr);
        setControlFont(g_bootstrapStatus, regularFont);
        setControlFont(g_updaterStatus, regularFont);
        setControlFont(g_details, regularFont);

        HWND safety = CreateWindowExW(0, L"STATIC",
            L"An updater is changed only after HTTPS, size, SHA-256, and version checks pass. Existing versions are backed up first.",
            WS_CHILD | WS_VISIBLE, 30, 280, 540, 35, window, nullptr,
            GetModuleHandleW(nullptr), nullptr);
        setControlFont(safety, regularFont);

        HWND closeButton = CreateWindowExW(0, L"BUTTON", L"Close",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
            475, 326, 95, 30, window, reinterpret_cast<HMENU>(IDCANCEL),
            GetModuleHandleW(nullptr), nullptr);
        setControlFont(closeButton, regularFont);

        // Fetch the release manifest once per launch. The same validated
        // response drives both Bootstrap and updater version statuses.
        startStatusCheck(window);
        return 0;
    }
    case kCheckCompleteMessage: {
        std::unique_ptr<CheckResult> result(reinterpret_cast<CheckResult *>(lParam));
        if (result) {
            // One manifest request determines both displayed version statuses.
            setControlText(g_bootstrapStatus, result->bootstrapStatus);
            setControlText(g_updaterStatus, result->updaterStatus);
            setControlText(g_details, result->details);
        }
        return 0;
    }
    case WM_COMMAND:
        if (LOWORD(wParam) == IDCANCEL) {
            DestroyWindow(window);
            return 0;
        }
        break;
    case WM_CLOSE:
        DestroyWindow(window);
        return 0;
    case WM_DESTROY:
        if (g_headingFont) {
            DeleteObject(g_headingFont);
            g_headingFont = nullptr;
        }
        g_bootstrapStatus = nullptr;
        g_updaterStatus = nullptr;
        g_details = nullptr;
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}
} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand) {
    INITCOMMONCONTROLSEX commonControls{sizeof(commonControls), ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&commonControls);

    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.lpfnWndProc = windowProcedure;
    windowClass.hInstance = instance;
    windowClass.hIcon = LoadIconW(nullptr, MAKEINTRESOURCEW(32512));
    windowClass.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
    windowClass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    windowClass.lpszClassName = kWindowClass;

    if (!RegisterClassExW(&windowClass)) {
        MessageBoxW(nullptr, L"Could not create the Argon Bootstrap window.",
                    L"Argon Bootstrap", MB_ICONERROR | MB_OK);
        return 1;
    }

    RECT rectangle{0, 0, 620, 400};
    AdjustWindowRectEx(&rectangle, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU
                       | WS_MINIMIZEBOX, FALSE, WS_EX_APPWINDOW);
    const int width = rectangle.right - rectangle.left;
    const int height = rectangle.bottom - rectangle.top;
    const int x = (GetSystemMetrics(SM_CXSCREEN) - width) / 2;
    const int y = (GetSystemMetrics(SM_CYSCREEN) - height) / 2;

    HWND window = CreateWindowExW(
        WS_EX_APPWINDOW, kWindowClass, L"Argon Bootstrap",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        x, y, width, height, nullptr, nullptr, instance, nullptr);
    if (!window) {
        MessageBoxW(nullptr, L"Could not create the Argon Bootstrap window.",
                    L"Argon Bootstrap", MB_ICONERROR | MB_OK);
        return 1;
    }

    ShowWindow(window, showCommand);
    UpdateWindow(window);
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return static_cast<int>(message.wParam);
}
