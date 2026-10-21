cmake_minimum_required(VERSION 3.21)
project(Argon VERSION 0.1.4 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Network)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(Argon
    src/main.cpp
    src/app/AppPaths.cpp
    src/app/AppPaths.h
    src/app/AppServices.cpp
    src/app/AppServices.h
    src/app/UserSettingsService.cpp
    src/app/UserSettingsService.h
    src/analytics/DailyAnalyticsService.cpp
    src/analytics/DailyAnalyticsService.h
    src/search/SearchService.cpp
    src/search/SearchService.h
    src/search/DropImportWorker.cpp
    src/search/DropImportWorker.h
    src/versioning/VersionNumber.cpp
    src/versioning/VersionNumber.h
    src/versioning/LatestReleaseMetadata.cpp
    src/versioning/LatestReleaseMetadata.h
    src/versioning/ReleaseMetadataService.cpp
    src/versioning/ReleaseMetadataService.h
    src/versioning/AppUpdateService.cpp
    src/versioning/AppUpdateService.h
    src/versioning/UpdaterStatusService.cpp
    src/versioning/UpdaterStatusService.h
)

qt_add_qml_module(Argon
    URI Argon
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/SideBar.qml
        qml/components/TimerController.qml
        qml/pages/TimerPage.qml
        qml/themes/Theme.qml
    RESOURCES
        qml/assets/icons/Settings/setting-icon.png
)

target_link_libraries(Argon PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
)

# This CMake project version is the application's single version source.
target_compile_definitions(Argon PRIVATE "ARGON_VERSION_STRING=\"${PROJECT_VERSION}\"")

# The bootstrap is a native Windows executable. It deliberately does not link
# Qt, so it can still open when the Qt runtime or Argon itself is damaged.
# It checks release metadata over HTTPS and only replaces an updater after
# validating package size, SHA-256, and embedded PE version.
if(WIN32)
    enable_language(RC)

    # Embed the Argon branding in the native Windows executable.
    set(ARGON_APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/qml/assets/branding/brand-logo-ico.ico")
    if(NOT EXISTS "${ARGON_APP_ICON}")
        message(FATAL_ERROR "Missing Argon executable icon: ${ARGON_APP_ICON}")
    endif()
    set(ARGON_APP_ICON_RC "${CMAKE_CURRENT_BINARY_DIR}/argon_app_icon.rc")
    file(TO_CMAKE_PATH "${ARGON_APP_ICON}" ARGON_APP_ICON_RC_PATH)
    file(WRITE "${ARGON_APP_ICON_RC}" "IDI_ICON1 ICON \"${ARGON_APP_ICON_RC_PATH}\"\n")
    target_sources(Argon PRIVATE "${ARGON_APP_ICON_RC}")


    # Version the active native updater independently from the application.
    # Bootstrap reads this executable version when validating updater packages.
    set(ARGON_UPDATER_VERSION "1.1.0.0" CACHE STRING "Argon Updater file version")
    if(NOT ARGON_UPDATER_VERSION MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
        message(FATAL_ERROR "ARGON_UPDATER_VERSION must use four numeric components (major.minor.patch.cosmetic).")
    endif()
    string(REPLACE "." "," ARGON_UPDATER_VERSION_RC "${ARGON_UPDATER_VERSION}")
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/bootstrap/argon_updater.manifest"
        "${CMAKE_CURRENT_BINARY_DIR}/argon_updater.manifest"
        COPYONLY
    )
    file(TO_CMAKE_PATH "${CMAKE_CURRENT_BINARY_DIR}/argon_updater.manifest" ARGON_UPDATER_MANIFEST_RC_PATH)
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/bootstrap/updater_version.rc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/argon_updater_version.rc"
        @ONLY
    )

    add_executable(ArgonUpdater WIN32
        bootstrap/updater_stub.cpp
        "${CMAKE_CURRENT_BINARY_DIR}/argon_updater_version.rc"
    )
    set_target_properties(ArgonUpdater PROPERTIES
        OUTPUT_NAME "ArgonUpdater"
        WIN32_EXECUTABLE TRUE
    )
    target_compile_definitions(ArgonUpdater PRIVATE
        "ARGON_APP_DIRECTORY_URL=\"https://raw.githubusercontent.com/mnotion/argon.updater/updater-intermediate/directory.json\""
    )
    target_link_libraries(ArgonUpdater PRIVATE winhttp bcrypt comctl32 shell32)
    if(MINGW)
        target_link_options(ArgonUpdater PRIVATE
            -municode
            -static
            -static-libgcc
            -static-libstdc++
        )
    endif()
    if(DEFINED ARGON_UPDATER_OUTPUT_DIR AND NOT ARGON_UPDATER_OUTPUT_DIR STREQUAL "")
        file(MAKE_DIRECTORY "${ARGON_UPDATER_OUTPUT_DIR}")
        set_target_properties(ArgonUpdater PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY "${ARGON_UPDATER_OUTPUT_DIR}"
        )
    endif()

    add_executable(ArgonBootstrap WIN32
        bootstrap/main.cpp
    )
    set_target_properties(ArgonBootstrap PROPERTIES
        OUTPUT_NAME "Bootstrap"
        WIN32_EXECUTABLE TRUE
    )

    # MinGW needs -municode to use the Unicode wWinMain entry point.
    if(MINGW)
        # Keep the standalone recovery executable independent of MinGW runtime DLLs.
        target_link_options(ArgonBootstrap PRIVATE
            -municode
            -static
            -static-libgcc
            -static-libstdc++
        )
    endif()
    # Keep the local version configurable and sourced from one CMake setting.
    set(ARGON_BOOTSTRAP_VERSION "1.0.0.0" CACHE STRING "Argon Bootstrap version")
    target_compile_definitions(ArgonBootstrap PRIVATE
        "ARGON_BOOTSTRAP_VERSION=\"${ARGON_BOOTSTRAP_VERSION}\""
        "ARGON_UPDATER_METADATA_URL=\"https://raw.githubusercontent.com/mnotion/argon.updater/rel-config/bootstrap-latest.json?rev=7\""
    )
    target_link_libraries(ArgonBootstrap PRIVATE
        winhttp
        bcrypt
        version
        comctl32
    )

    # The dev launcher supplies a clean staging destination. Without it, CMake's
    # normal target output directory is used for direct developer builds.
    if(DEFINED ARGON_BOOTSTRAP_OUTPUT_DIR AND NOT ARGON_BOOTSTRAP_OUTPUT_DIR STREQUAL "")
        file(MAKE_DIRECTORY "${ARGON_BOOTSTRAP_OUTPUT_DIR}")
        set_target_properties(ArgonBootstrap PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY "${ARGON_BOOTSTRAP_OUTPUT_DIR}"
        )
    endif()
endif()

# Optional external runtime output directory used by build.bat to assemble
# the runnable desktop Argon-sim bundle. Build intermediates stay in build/.
if(DEFINED ARGON_RUNTIME_OUTPUT_DIR AND NOT ARGON_RUNTIME_OUTPUT_DIR STREQUAL "")
    file(MAKE_DIRECTORY "${ARGON_RUNTIME_OUTPUT_DIR}")
    set_target_properties(Argon PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${ARGON_RUNTIME_OUTPUT_DIR}"
    )
endif()

if(WIN32)
    set_target_properties(Argon PROPERTIES WIN32_EXECUTABLE TRUE)
endif()

# Versioning logic tests are opt-in so normal app builds stay lean.
option(ARGON_BUILD_VERSIONING_TESTS "Build offline versioning and user-settings tests" OFF)
if(ARGON_BUILD_VERSIONING_TESTS)
    enable_testing()
    add_executable(ArgonVersioningTests
        tests/versioning/VersioningTests.cpp
        src/versioning/VersionNumber.cpp
        src/versioning/VersionNumber.h
        src/versioning/LatestReleaseMetadata.cpp
        src/versioning/LatestReleaseMetadata.h
    )
    target_include_directories(ArgonVersioningTests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src/versioning"
    )
    target_link_libraries(ArgonVersioningTests PRIVATE Qt6::Core)
    add_test(NAME ArgonVersioningTests COMMAND ArgonVersioningTests)

    add_executable(ArgonUserSettingsTests
        tests/app/UserSettingsServiceTests.cpp
        src/app/UserSettingsService.cpp
        src/app/UserSettingsService.h
        src/app/AppPaths.cpp
        src/app/AppPaths.h
    )
    target_include_directories(ArgonUserSettingsTests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src/app"
    )
    target_link_libraries(ArgonUserSettingsTests PRIVATE Qt6::Core)
    add_test(NAME ArgonUserSettingsTests COMMAND ArgonUserSettingsTests)
endif()
