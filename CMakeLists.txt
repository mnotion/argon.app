cmake_minimum_required(VERSION 3.21)
project(Argon VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Pdf PdfQuick Network)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(Argon
    src/main.cpp
    src/app/AppPaths.cpp
    src/app/AppPaths.h
    src/app/AppServices.cpp
    src/app/AppServices.h
    src/analytics/DailyAnalyticsService.cpp
    src/analytics/DailyAnalyticsService.h
    src/documents/DocumentService.cpp
    src/documents/DocumentService.h
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
)

qt_add_qml_module(Argon
    URI Argon
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/SideBar.qml
        qml/components/TimerController.qml
        qml/components/TopBar.qml
        qml/components/WorkspaceCard.qml
        qml/pages/NotesPage.qml
        qml/pages/TimerPage.qml
        qml/pages/ResourcesPage.qml
        qml/pages/AnalyticsPage.qml
        qml/pages/DocPage.qml
        qml/themes/Theme.qml
    RESOURCES
        qml/assets/icons/Settings/setting-icon.png
)

target_link_libraries(Argon PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Pdf
    Qt6::PdfQuick
    Qt6::Network
)

# This CMake project version is the application's single version source.
target_compile_definitions(Argon PRIVATE "ARGON_VERSION_STRING=\"${PROJECT_VERSION}\"")

# The bootstrap is a native Windows executable. It deliberately does not link
# Qt, so it can still open when the Qt runtime or Argon itself is damaged.
# It checks release metadata over HTTPS and only replaces an updater after
# validating package size, SHA-256, and embedded PE version.
if(WIN32)
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
    target_compile_definitions(ArgonBootstrap PRIVATE
        "ARGON_BOOTSTRAP_VERSION=\"1.0.0.0\""
        "ARGON_BOOTSTRAP_LATEST_URL=\"https://raw.githubusercontent.com/mnotion/argon.updater/rel-config/bootstrap-latest.json?rev=2\""
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
option(ARGON_BUILD_VERSIONING_TESTS "Build offline tests for Argon versioning" OFF)
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
endif()
