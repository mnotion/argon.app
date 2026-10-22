import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import "components"
import "pages"
import "themes"

ApplicationWindow {
    id: window
    width: 1280
    height: 820
    minimumWidth: 900
    minimumHeight: 620
    visible: true
    title: "Argon"
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"

    Theme {
        id: theme
        lightMode: window.lightMode
        accent: window.accentColor
    }
    TimerController { id: timerControllerInstance }
    property string activePage: "Search"
    property bool settingsOpen: false
    property bool settingsExpanded: false
    property real settingsBaseY: 0
    property bool profileOpen: false
    property bool profileExpanded: false
    property real profileBaseY: 0
    property bool demoLoggedIn: false
    property string demoUsername: ""
    property string profileMessage: ""
    property bool lightMode: false
    property color accentColor: "#8CBFFF"
    readonly property var accentPalette: [
        "#8CBFFF", "#58A6FF", "#9B8AFB", "#D98CEB", "#F18AAB",
        "#F28C6B", "#F2C14E", "#8CCF7E", "#4CC9B0", "#8A99A8"
    ]
    property bool searchCaseSensitive: false
    property bool searchIncludeHidden: false
    property bool timerSoundEnabled: true
    property bool universalTimerView: false
    property bool argonExplorerOpen: false
    property bool dropHoverActive: false
    property string argonExplorerCurrentPath: ""
    property var argonExplorerEntries: []
    property bool appUpdatePromptShown: false
    property bool settingsLoaded: false

    function persistSetting(key, value) {
        if (!window.settingsLoaded)
            return
        if (!appSettingsService.setValue(key, value))
            console.warn("[Settings] Could not persist setting:", key)
    }

    function loadPersistentSettings() {
        // Do not write defaults while loading the stored values.
        window.settingsLoaded = false

        window.lightMode = appSettingsService.value("preferences.lightMode", false)
        var storedAccent = String(appSettingsService.value("preferences.accentColor", "#8CBFFF"))
        window.accentColor = window.accentPalette.indexOf(storedAccent) >= 0
                ? storedAccent : "#8CBFFF"
        window.searchCaseSensitive = appSettingsService.value("preferences.searchCaseSensitive", false)
        window.searchIncludeHidden = appSettingsService.value("preferences.searchIncludeHidden", false)
        window.timerSoundEnabled = appSettingsService.value("preferences.timerSoundEnabled", true)
        window.universalTimerView = appSettingsService.value("preferences.universalTimerView", false)

        var savedPage = String(appSettingsService.value("ui.activePage", "Search"))
        var validPages = ["Search", "Timer"]
        if (validPages.indexOf(savedPage) !== -1)
            window.activePage = savedPage

        window.settingsLoaded = true
    }

    function savePersistentSettings() {
        if (!window.settingsLoaded)
            return

        appSettingsService.setValue("preferences.lightMode", window.lightMode)
        appSettingsService.setValue("preferences.accentColor", String(window.accentColor))
        appSettingsService.setValue("preferences.searchCaseSensitive", window.searchCaseSensitive)
        appSettingsService.setValue("preferences.searchIncludeHidden", window.searchIncludeHidden)
        appSettingsService.setValue("preferences.timerSoundEnabled", window.timerSoundEnabled)
        appSettingsService.setValue("preferences.universalTimerView", window.universalTimerView)
        appSettingsService.setValue("ui.activePage", window.activePage)
        appSettingsService.sync()
    }

    Component.onCompleted: {
        window.loadPersistentSettings()
        if (appUpdateService.state === "installed" || appUpdateService.state === "failed")
            updateResultDialog.open()
    }

    onClosing: {
        window.savePersistentSettings()
        timerControllerInstance.persistElapsedState()
    }

    // One concise status covers the application and companion updater.
    property color releaseStatusColor: {
        if (releaseMetadataService.checking || updaterStatusService.checking)
            return "#E5B83B"
        if ((releaseMetadataService.checkSucceeded && releaseMetadataService.updateAvailable)
                || (updaterStatusService.checkSucceeded && updaterStatusService.updateAvailable))
            return "#E34B4B"
        if (releaseMetadataService.checkSucceeded && updaterStatusService.checkSucceeded)
            return "#36B56B"
        return "#888888"
    }
    property string releaseStatusText: {
        if (releaseMetadataService.checking || updaterStatusService.checking)
            return "Checking"
        if ((releaseMetadataService.checkSucceeded && releaseMetadataService.updateAvailable)
                || (updaterStatusService.checkSucceeded && updaterStatusService.updateAvailable))
            return "Update available"
        if (releaseMetadataService.checkSucceeded && updaterStatusService.checkSucceeded)
            return "Up to date"
        if (releaseMetadataService.checkSucceeded || updaterStatusService.checkSucceeded)
            return "Partially checked"
        return "Unavailable"
    }

    function toggleFullscreen() {
        if (window.visibility === Window.FullScreen) {
            window.showNormal()
        } else {
            window.showFullScreen()
        }
    }

    onActivePageChanged: {
        window.persistSetting("ui.activePage", window.activePage)
        if (activePage !== "Search") {
            argonExplorerOpen = false
        }
    }
    onLightModeChanged: window.persistSetting("preferences.lightMode", window.lightMode)
    onAccentColorChanged: window.persistSetting("preferences.accentColor", String(window.accentColor))
    onSearchCaseSensitiveChanged: window.persistSetting("preferences.searchCaseSensitive", window.searchCaseSensitive)
    onSearchIncludeHiddenChanged: window.persistSetting("preferences.searchIncludeHidden", window.searchIncludeHidden)
    onTimerSoundEnabledChanged: window.persistSetting("preferences.timerSoundEnabled", window.timerSoundEnabled)
    onUniversalTimerViewChanged: window.persistSetting("preferences.universalTimerView", window.universalTimerView)

    function refreshArgonExplorerEntries() {
        if (argonExplorerCurrentPath.length === 0)
            argonExplorerCurrentPath = searchService.searchRoot
        argonExplorerEntries = searchService.listFolderContents(argonExplorerCurrentPath)
    }

    function openArgonExplorer() {
        if (!argonExplorerOpen)
            argonExplorerCurrentPath = searchService.searchRoot
        refreshArgonExplorerEntries()
        argonExplorerOpen = true
    }

    function openArgonExplorerAtPath(path) {
        argonExplorerCurrentPath = path
        refreshArgonExplorerEntries()
        argonExplorerOpen = true
    }

    function goBackArgonExplorer() {
        var rootPath = searchService.searchRoot
        var currentPath = argonExplorerCurrentPath
        if (currentPath.toLowerCase() === rootPath.toLowerCase()) {
            argonExplorerOpen = false
            return
        }

        var separator = Math.max(currentPath.lastIndexOf("/"), currentPath.lastIndexOf("\\"))
        var parentPath = separator < 0 ? rootPath : currentPath.substring(0, separator)
        if (parentPath.toLowerCase().indexOf(rootPath.toLowerCase()) !== 0)
            parentPath = rootPath

        argonExplorerCurrentPath = parentPath
        refreshArgonExplorerEntries()
    }

    Shortcut {
        sequence: "F11"
        onActivated: window.toggleFullscreen()
    }

    Rectangle {
        id: windowSurface
        anchors.fill: parent
        radius: window.visibility === Window.FullScreen ? 0 : 16
        color: theme.window
        border.color: window.visibility === Window.FullScreen ? "transparent" : theme.border
        border.width: window.visibility === Window.FullScreen ? 0 : 1
        antialiasing: true
        z: -2
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: {
            sideBar.bannerOpen = false
            window.settingsOpen = false
            window.profileOpen = false
            window.settingsExpanded = false
            window.profileExpanded = false
        }
    }

    Rectangle {
        id: contextualSettings
        Component.onCompleted: settingsBaseY = window.height * 0.25 - height / 2
        width: 292
        height: (settingsColumn.implicitHeight + 42) * (window.settingsExpanded ? 2 : 1)
        property bool tuckedByNavigation: sideBar.bannerOpen
        x: window.settingsOpen ? window.width - width - 10 : (tuckedByNavigation ? window.width - 24 : window.width)
        y: settingsBaseY
        z: 150
        radius: 14
        visible: window.settingsOpen || x < window.width
        color: Qt.rgba(theme.surfaceRaised.r, theme.surfaceRaised.g, theme.surfaceRaised.b, 0.97)
        border.color: theme.border
        border.width: 1
        clip: false
        opacity: window.settingsOpen ? 1 : (sideBar.bannerOpen ? 0.55 : 0)
        Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.OutExpo } }
        Behavior on height { NumberAnimation { duration: 440; easing.type: Easing.OutExpo } }
        Connections {
            target: sideBar
            function onBannerOpenChanged() {
                if (!sideBar.bannerOpen) {
                    window.settingsOpen = false
                    window.profileOpen = false
                    window.settingsExpanded = false
                    window.profileExpanded = false
                }
            }
        }
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        ColumnLayout {
            id: settingsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 14
            spacing: 10
            height: implicitHeight
            opacity: window.settingsOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: window.activePage + " settings"; color: theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }
                Button {
                    text: "×"
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    flat: true
                    onClicked: {
                        window.settingsOpen = false
                        window.settingsExpanded = false
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.hovered ? theme.surfaceRaised : "transparent"
                    }
                    contentItem: Text {
                        text: "×"
                        color: theme.text
                        font.pixelSize: 22
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Light mode"; color: theme.text; font.pixelSize: 13 }
                Switch { checked: window.lightMode; onToggled: window.lightMode = checked }
            }
            Text {
                Layout.fillWidth: true
                text: "Accent colour"
                color: theme.text
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: window.accentPalette
                    delegate: Rectangle {
                        required property color modelData
                        Layout.preferredWidth: 19
                        Layout.preferredHeight: 19
                        radius: 10
                        color: modelData
                        border.width: String(window.accentColor) === String(modelData) ? 3 : 1
                        border.color: String(window.accentColor) === String(modelData)
                                      ? theme.text : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.28)
                        scale: accentSwatchMouse.containsMouse ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        MouseArea {
                            id: accentSwatchMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.accentColor = String(modelData)
                        }
                    }
                }
            }
            Text { Layout.fillWidth: true; visible: window.activePage === "Search"; text: "Search options"; color: theme.accent; font.pixelSize: 12; font.weight: Font.DemiBold }
            RowLayout {
                Layout.fillWidth: true
                visible: window.activePage === "Search"
                Text { Layout.fillWidth: true; text: "Case-sensitive search"; color: theme.text; font.pixelSize: 12 }
                Switch { checked: window.searchCaseSensitive; onToggled: window.searchCaseSensitive = checked }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: window.activePage === "Search"
                Text { Layout.fillWidth: true; text: "Include hidden files"; color: theme.text; font.pixelSize: 12 }
                Switch { checked: window.searchIncludeHidden; onToggled: window.searchIncludeHidden = checked }
            }
            Text { Layout.fillWidth: true; visible: window.activePage === "Timer"; text: "Timer options"; color: theme.accent; font.pixelSize: 12; font.weight: Font.DemiBold }
            RowLayout {
                Layout.fillWidth: true
                visible: window.activePage === "Timer"
                Text { Layout.fillWidth: true; text: "Timer sounds"; color: theme.text; font.pixelSize: 12 }
                Switch { checked: window.timerSoundEnabled; onToggled: window.timerSoundEnabled = checked }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: window.activePage === "Timer"
                Text { Layout.fillWidth: true; text: "Universal view"; color: theme.text; font.pixelSize: 12 }
                Switch { checked: window.universalTimerView; onToggled: window.universalTimerView = checked }
            }
        }

    }

    Rectangle {
        id: settingsExpandHandle
        x: contextualSettings.x + (contextualSettings.width - width) / 2
        y: contextualSettings.y + contextualSettings.height + 4
        width: 52
        height: 22
        radius: 7
        z: 151
        visible: contextualSettings.visible
        opacity: (window.settingsOpen || sideBar.bannerOpen) ? 1 : 0
        color: settingsHandleMouse.containsMouse ? theme.surfaceRaised : theme.surface
        border.color: theme.border
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: 2
                delegate: Row {
                    spacing: 4
                    Repeater { model: 3; delegate: Rectangle { width: 3; height: 3; radius: 2; color: theme.mutedText } }
                }
            }
        }
        MouseArea {
            id: settingsHandleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: window.settingsExpanded = !window.settingsExpanded
        }
    }

    Rectangle {
        id: profilePanel
        Component.onCompleted: profileBaseY = Math.max(12, Math.min(window.height - height - 12, window.height * 0.25 - height / 2))
        width: 292
        height: Math.min(window.height - 24, (profileColumn.implicitHeight + 30) * (window.profileExpanded ? 1.08 : 1))
        property bool tuckedByNavigation: sideBar.bannerOpen
        x: window.profileOpen ? 10 : (tuckedByNavigation ? -width + 24 : -width)
        y: profileBaseY
        z: 150
        radius: 14
        visible: window.profileOpen || x > -width
        color: Qt.rgba(theme.surfaceRaised.r, theme.surfaceRaised.g, theme.surfaceRaised.b, 0.97)
        border.color: theme.border
        border.width: 1
        clip: true
        opacity: window.profileOpen ? 1 : (sideBar.bannerOpen ? 0.55 : 0)
        Behavior on x { NumberAnimation { duration: 520; easing.type: Easing.OutExpo } }
        Behavior on height { NumberAnimation { duration: 440; easing.type: Easing.OutExpo } }
        onHeightChanged: profileBaseY = Math.max(12, Math.min(window.height - height - 12, window.height * 0.25 - height / 2))
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Connections {
            target: sideBar
            function onBannerOpenChanged() {
                if (!sideBar.bannerOpen) {
                    window.profileOpen = false
                    window.settingsOpen = false
                    window.profileExpanded = false
                    window.settingsExpanded = false
                }
            }
        }
        ColumnLayout {
            id: profileColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 14
            anchors.bottomMargin: 32
            spacing: 10
            opacity: window.profileOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            RowLayout {
                Layout.fillWidth: true
                spacing: 7
                Text { text: "Account"; color: theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }

                Item { Layout.fillWidth: true }

                Button {
                    text: "×"
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    flat: true
                    onClicked: {
                        window.profileOpen = false
                        window.profileExpanded = false
                    }
                    background: Rectangle { radius: 8; color: parent.hovered ? theme.surfaceRaised : "transparent" }
                    contentItem: Text { text: "×"; color: theme.text; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }

            RowLayout {
                Layout.fillWidth: true
                visible: !window.profileExpanded
                spacing: 6

                Text {
                    text: "Updates"
                    color: theme.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: "— " + window.releaseStatusText
                    color: window.releaseStatusColor
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: updatesCard
                Layout.fillWidth: true
                visible: window.profileExpanded
                radius: 12
                color: theme.surface
                border.color: theme.border
                implicitHeight: updatesColumn.implicitHeight + 20

                ColumnLayout {
                    id: updatesColumn
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Text {
                            text: "Argon"
                            color: theme.accent
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Installed: " + (releaseMetadataService.currentVersion.length > 0
                                                   ? releaseMetadataService.currentVersion : "unknown")
                            color: theme.text
                            font.pixelSize: 12
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Stable: " + (releaseMetadataService.latestVersion.length > 0
                                                 ? releaseMetadataService.latestVersion : "checking")
                            color: theme.mutedText
                            font.pixelSize: 12
                        }
                        Button {
                            visible: releaseMetadataService.checkSucceeded
                                     && releaseMetadataService.updateAvailable
                            text: (appUpdateService.downloaded
                                   && appUpdateService.targetVersion === releaseMetadataService.latestVersion)
                                  ? "Install update"
                                  : (appUpdateService.downloading ? "Downloading…" : "Review update")
                            enabled: !appUpdateService.installing
                            onClicked: appUpdateDialog.open()
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: theme.border }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Text {
                            text: "Updater"
                            color: theme.accent
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Installed: " + (updaterStatusService.installedVersion.length > 0
                                                   ? updaterStatusService.installedVersion : "unknown")
                            color: theme.text
                            font.pixelSize: 12
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Stable: " + (updaterStatusService.latestVersion.length > 0
                                                 ? updaterStatusService.latestVersion : "checking")
                            color: theme.mutedText
                            font.pixelSize: 12
                        }
                        Button {
                            visible: updaterStatusService.checkSucceeded
                                     && updaterStatusService.updateAvailable
                                     && updaterStatusService.packageAvailable
                            text: "Update"
                            onClicked: updaterInstallDialog.open()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    width: 46
                    height: 46
                    radius: 23
                    color: theme.surfaceRaised
                    border.color: theme.border
                    Text {
                        anchors.centerIn: parent
                        text: window.demoLoggedIn && window.demoUsername.length > 0
                              ? window.demoUsername.charAt(0).toUpperCase() : "●"
                        color: theme.accent
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: window.demoLoggedIn ? window.demoUsername : "Guest account"
                        color: theme.text
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.demoLoggedIn ? "Local demo profile" : "Not signed in"
                        color: theme.mutedText
                        font.pixelSize: 11
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: window.demoLoggedIn ? "Profile" : "Sign in to your demo profile"
                color: theme.accent
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            TextField {
                id: profileUsername
                Layout.fillWidth: true
                visible: !window.demoLoggedIn
                placeholderText: "Username"
                color: theme.text
                selectByMouse: true
                background: Rectangle {
                    radius: 8
                    color: theme.surface
                    border.color: profileUsername.activeFocus ? theme.accent : theme.border
                }
            }

            TextField {
                id: profilePassword
                Layout.fillWidth: true
                visible: !window.demoLoggedIn
                placeholderText: "Password (demo only)"
                echoMode: TextInput.Password
                color: theme.text
                selectByMouse: true
                background: Rectangle {
                    radius: 8
                    color: theme.surface
                    border.color: profilePassword.activeFocus ? theme.accent : theme.border
                }
            }

            Text {
                Layout.fillWidth: true
                visible: window.profileMessage.length > 0
                text: window.profileMessage
                color: theme.accent
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true
                    text: window.demoLoggedIn ? "Sign out" : "Log in"
                    onClicked: {
                        if (window.demoLoggedIn) {
                            window.demoLoggedIn = false
                            window.demoUsername = ""
                            window.profileMessage = "Signed out of the demo profile."
                            profilePassword.text = ""
                            profileUsername.text = ""
                        } else if (profileUsername.text.trim().length === 0 || profilePassword.text.length === 0) {
                            window.profileMessage = "Enter a username and password to try the demo."
                        } else {
                            window.demoUsername = profileUsername.text.trim()
                            window.demoLoggedIn = true
                            window.profileMessage = "Demo login successful. No account was created and no credentials were sent or saved."
                            profilePassword.text = ""
                        }
                    }
                }
                Button {
                    visible: !window.demoLoggedIn
                    text: "Guest"
                    onClicked: {
                        window.demoUsername = "Guest"
                        window.demoLoggedIn = true
                        window.profileMessage = "Continuing as a guest demo profile."
                        profilePassword.text = ""
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Demo only — authentication is not connected to a server."
                color: theme.mutedText
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }

    }

 
    Rectangle {
        id: profileExpandHandle
        x: profilePanel.x + (profilePanel.width - width) / 2
        y: profilePanel.y + profilePanel.height + 4
        width: 52
        height: 22
        radius: 7
        z: 151
        visible: profilePanel.visible
        opacity: (window.profileOpen || sideBar.bannerOpen) ? 1 : 0
        color: profileHandleMouse.containsMouse ? theme.surfaceRaised : theme.surface
        border.color: theme.border
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: 2
                delegate: Row {
                    spacing: 4
                    Repeater { model: 3; delegate: Rectangle { width: 3; height: 3; radius: 2; color: theme.mutedText } }
                }
            }
        }
        MouseArea {
            id: profileHandleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: window.profileExpanded = !window.profileExpanded
        }
    }

    Rectangle {
        id: fullscreenButton
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: 64
        height: 56
        radius: 15
        z: 200
        visible: sideBar.bannerOpen || opacity > 0.01
        opacity: sideBar.bannerOpen ? 1 : 0
        scale: sideBar.bannerOpen ? 1 : 0.86
        color: fullscreenMouse.containsMouse ? theme.surfaceRaised : theme.surface
        border.color: fullscreenMouse.containsMouse ? theme.accent : theme.border
        border.width: 1
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutExpo } }

        Text {
            anchors.centerIn: parent
            text: "⛶"
            color: theme.text
            font.pixelSize: 30
        }

        MouseArea {
            id: fullscreenMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: window.toggleFullscreen()
        }
    }

    Rectangle {
        id: windowEdge
        anchors.fill: parent
        radius: window.visibility === Window.FullScreen ? 0 : 16
        color: "transparent"
        border.color: window.visibility === Window.FullScreen ? "transparent" : theme.border
        border.width: window.visibility === Window.FullScreen ? 0 : 1
        antialiasing: true
        z: 100
        // Keep the border visible without intercepting window interaction.
        enabled: false
    }

    ColumnLayout {
        id: appContentLayout
        anchors.fill: parent
        anchors.margins: window.visibility === Window.FullScreen ? 0 : 1
        spacing: 0

        // Blur the app surface behind Explorer and file-action dialogs.
        // Both popups are siblings of this layout, so their contents stay sharp.
        layer.effect: MultiEffect {
            blurMax: 48
            Behavior on blur {
                NumberAnimation {
                    duration: 340
                    easing.type: Easing.OutCubic
                }
            }
        }

        Rectangle {
            id: titleBar
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 38 : 0
            visible: window.visibility !== Window.FullScreen
            z: 40
            radius: 0
            topLeftRadius: window.visibility === Window.FullScreen ? 0 : 16
            topRightRadius: window.visibility === Window.FullScreen ? 0 : 16
            bottomLeftRadius: 0
            bottomRightRadius: 0
            clip: true
            color: theme.titleBar
            border.color: "transparent"
            border.width: 0

            // Drag only the empty title-bar area; keep the controls independent.
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: 126
                z: 1
                onPressed: window.startSystemMove()
                onDoubleClicked: window.visibility === Window.Maximized ? window.showNormal() : window.showMaximized()
            }

            Row {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 0
                z: 2

                Rectangle {
                    width: 42
                    height: titleBar.height
                    color: minimizeArea.containsMouse ? theme.surfaceRaised : "transparent"
                    MouseArea {
                        id: minimizeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: window.showMinimized()
                    }
                    Text { anchors.centerIn: parent; text: "—"; color: theme.text; font.pixelSize: 14 }
                }

                Rectangle {
                    width: 42
                    height: titleBar.height
                    color: maximizeArea.containsMouse ? theme.surfaceRaised : "transparent"
                    MouseArea {
                        id: maximizeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: window.visibility === Window.Maximized ? window.showNormal() : window.showMaximized()
                    }
                    Text {
                        anchors.centerIn: parent
                        text: window.visibility === Window.Maximized ? "❐" : "□"
                        color: theme.text
                        font.pixelSize: 13
                    }
                }

                Rectangle {
                    width: 46
                    height: titleBar.height
                    radius: 0
                    topRightRadius: closeArea.containsMouse && window.visibility !== Window.FullScreen ? 16 : 0
                    bottomRightRadius: 0
                    color: closeArea.containsMouse ? "#b94a4a" : "transparent"
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: window.close()
                    }
                    Text { anchors.centerIn: parent; text: "×"; color: theme.text; font.pixelSize: 19 }
                }
            }
        }

        SideBar {
            id: sideBar
            z: 30
            Layout.fillWidth: true
            activePage: window.activePage
            lightMode: window.lightMode
            accentColor: window.accentColor
            onPageSelected: function(pageName) {
                window.activePage = pageName
                window.settingsOpen = false
                window.profileOpen = false
                sideBar.bannerOpen = false
            }
            onFullscreenRequested: window.toggleFullscreen()
            onSettingsRequested: {
                window.profileOpen = false
                window.settingsOpen = !window.settingsOpen
            }
            onProfileRequested: {
                window.settingsOpen = false
                window.profileOpen = !window.profileOpen
            }
            clip: false
        }

        Loader {
            id: pageLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Render the page directly at native resolution unless the sidebar
            // actually needs the blurred backdrop. This avoids persistent
            // off-screen compositing softening text in the normal window.
            enabled: !sideBar.bannerOpen
            layer.enabled: sideBar.bannerOpen
            layer.effect: MultiEffect {
                blurEnabled: sideBar.bannerOpen
                blur: sideBar.bannerOpen ? 0.85 : 0
                blurMax: 48
                Behavior on blur {
                    NumberAnimation {
                        duration: 520
                        easing.type: Easing.InOutCubic
                    }
                }
            }
            sourceComponent: window.activePage === "Timer" ? timerPage : searchPage
        }

    }

    // This is parented to pageLoader so it follows every page and shares
    // the same blur effect while the sidebar is open.
    Item {
        id: universalTimerOverlay
        parent: pageLoader
        x: 18
        y: 14
        width: 204
        height: 56
        z: 500
        visible: window.universalTimerView
        enabled: !sideBar.bannerOpen
        property bool idle: false

        function noteActivity() {
            idle = false
            idleTimer.restart()
        }

        Timer {
            id: idleTimer
            interval: 60000
            repeat: false
            running: universalTimerOverlay.visible && !sideBar.bannerOpen
            onTriggered: universalTimerOverlay.idle = true
        }

        Behavior on opacity {
            NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
        }
        opacity: idle ? 0.075 : (sideBar.bannerOpen ? 0.45 : 1)

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3
            radius: 14
            color: Qt.rgba(0, 0, 0, 0.16)
            z: -1
        }

        Rectangle {
            anchors.fill: parent
            radius: 13
            color: Qt.rgba(0.10, 0.10, 0.10, 0.16)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: timerControllerInstance.formattedTime()
                    color: theme.text
                    font.pixelSize: 23
                    font.weight: Font.DemiBold
                    font.kerning: false
                    verticalAlignment: Text.AlignVCenter
                }

                Button {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    flat: true
                    text: timerControllerInstance.timerRunning ? "Ⅱ" : "▶"
                    ToolTip.visible: hovered
                    ToolTip.text: timerControllerInstance.timerRunning ? "Pause stopwatch" : "Resume stopwatch"
                    onClicked: {
                        universalTimerOverlay.noteActivity()
                        timerControllerInstance.toggleTimer()
                    }

                    background: Rectangle {
                        radius: 10
                        color: parent.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                        border.color: parent.hovered ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                    }

                    contentItem: Text {
                        text: parent.text
                        color: theme.text
                        font.pixelSize: timerControllerInstance.timerRunning ? 18 : 16
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            HoverHandler {
                onPointChanged: universalTimerOverlay.noteActivity()
                onHoveredChanged: if (hovered) universalTimerOverlay.noteActivity()
            }
        }
    }

    // Passive input tracking lets activity elsewhere in Argon wake the compact timer.
    HoverHandler {
        onPointChanged: universalTimerOverlay.noteActivity()
    }

    Item {
        id: argonExplorerPopup
        parent: window.contentItem
        x: appContentLayout.x + pageLoader.x
        y: appContentLayout.y + pageLoader.y
        width: pageLoader.width
        height: pageLoader.height
        z: 800
        visible: window.argonExplorerOpen && window.activePage === "Search"
        enabled: visible

        Rectangle {
            anchors.fill: parent
            color: "#24000000"
            z: 0

            MouseArea {
                anchors.fill: parent
                onClicked: window.argonExplorerOpen = false
            }
        }

        Rectangle {
            id: argonExplorerPanel
            width: Math.min(520, parent.width - 40)
            height: Math.min(500, parent.height - 40)
            anchors.centerIn: parent
            radius: 14
            color: theme.surface
            border.color: window.dropHoverActive ? theme.accent : theme.border
            border.width: window.dropHoverActive ? 1.5 : 1
            clip: true
            z: 1

            Behavior on border.color { ColorAnimation { duration: 140 } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 34
                    radius: 9
                    color: explorerBackMouse.containsMouse ? theme.surfaceRaised : "transparent"
                    border.color: explorerBackMouse.containsMouse ? theme.border : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        color: theme.text
                        font.pixelSize: 22
                    }

                    MouseArea {
                        id: explorerBackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.goBackArgonExplorer()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 9
                    color: Qt.rgba(0, 0, 0, 0.08)
                    clip: true

                    ListView {
                        id: argonExplorerEntriesList
                        anchors.fill: parent
                        anchors.margins: 5
                        model: window.argonExplorerEntries
                        clip: true
                        spacing: 1

                        delegate: Item {
                            required property var modelData
                            width: argonExplorerEntriesList.width
                            height: 40
                            opacity: modelData.isFolder ? 1.0 : 0.18

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 10

                                Item {
                                    width: 19
                                    height: 17
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.isFolder

                                    Rectangle {
                                        x: 1
                                        y: 5
                                        width: 17
                                        height: 11
                                        radius: 2
                                        color: "transparent"
                                        border.color: theme.text
                                        border.width: 1.2
                                    }

                                    Rectangle {
                                        x: 2
                                        y: 2
                                        width: 7
                                        height: 5
                                        radius: 1
                                        color: "transparent"
                                        border.color: theme.text
                                        border.width: 1.1
                                    }
                                }

                                Item {
                                    width: 19
                                    height: 17
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !modelData.isFolder

                                    Rectangle {
                                        x: 4
                                        y: 1
                                        width: 11
                                        height: 15
                                        radius: 1
                                        color: "transparent"
                                        border.color: theme.text
                                        border.width: 1.1
                                    }

                                    Rectangle {
                                        x: 6
                                        y: 5
                                        width: 7
                                        height: 1
                                        color: theme.text
                                    }

                                    Rectangle {
                                        x: 6
                                        y: 8
                                        width: 7
                                        height: 1
                                        color: theme.text
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 42
                                    text: modelData.name
                                    color: theme.text
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.isFolder) {
                                        window.argonExplorerCurrentPath = modelData.path
                                        window.refreshArgonExplorerEntries()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: argonExplorerPanel.radius
                clip: true
                visible: searchService.importInProgress
                color: Qt.rgba(0.06, 0.06, 0.06, 0.84)
                z: 10

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 36, 280)
                    spacing: 14

                    BusyIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 36
                        height: 36
                        running: searchService.importInProgress
                    }

                    Text {
                        width: parent.width
                        text: searchService.importStatus
                        color: theme.text
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                    }

                    ProgressBar {
                        width: parent.width
                        from: 0
                        to: 100
                        value: searchService.importProgressPercent
                    }

                    Text {
                        width: parent.width
                        text: searchService.importProgressPercent + "%"
                        color: theme.mutedText
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    DropArea {
        id: searchImportDropArea
        parent: window.contentItem
        x: appContentLayout.x + pageLoader.x
        y: appContentLayout.y + pageLoader.y
        width: pageLoader.width
        height: pageLoader.height
        z: 900
        enabled: window.activePage === "Search"

        onEntered: function(drag) {
            if (!drag.hasUrls)
                return
            window.dropHoverActive = true
            if (!window.argonExplorerOpen)
                window.openArgonExplorer()
        }

        onExited: {
            window.dropHoverActive = false
        }

        onDropped: function(drop) {
            window.dropHoverActive = false

            if (!drop.hasUrls) {
                drop.accepted = false
                return
            }

            var urlStrings = []
            for (var i = 0; i < drop.urls.length; ++i)
                urlStrings.push(drop.urls[i].toString())

            if (!window.argonExplorerOpen)
                window.openArgonExplorer()

            const importStarted = searchService.importDroppedUrls(
                        urlStrings, window.argonExplorerCurrentPath)
            if (importStarted) {
                // This operation copies into search QR; explicitly keep the
                // source items at their original location.
                drop.setDropAction(Qt.CopyAction)
                drop.accept()
            } else {
                drop.accepted = false
            }
        }
    }

    Connections {
        target: searchService
        function onDropImportFinished(succeeded, message) {
            window.refreshArgonExplorerEntries()
            window.dropHoverActive = false
        }
    }

    Component {
        id: searchPage

        Item {
            id: searchPlaceholder
            Theme {
            id: searchTheme
            lightMode: window.lightMode
            accent: window.accentColor
        }

            property string query: ""
            property var results: []
            property int currentPage: 0
            readonly property int resultsPerPage: 20
            property bool hasMoreResults: false
            property bool searchPending: false
            readonly property int loadedPageCount: Math.ceil(results.length / resultsPerPage)
            readonly property var pageResults: results.slice(
                currentPage * resultsPerPage,
                (currentPage + 1) * resultsPerPage)

            function performSearch(searchText) {
                var response = searchService.startNameSearch(searchText)
                results = response.results || []
                hasMoreResults = response.hasMore === true
                currentPage = 0
                searchPending = false
            }

            Rectangle {
                anchors.fill: parent
                color: searchTheme.window
            }

            Timer {
                id: searchDebounce
                interval: 180
                repeat: false
                onTriggered: searchPlaceholder.performSearch(searchInput.text)
            }

            Timer {
                interval: 70
                repeat: false
            }

            Column {
                id: searchContentColumn
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Math.max(90, parent.height * 0.26)
                width: Math.min(900, parent.width - 64)
                height: Math.max(0, parent.height - anchors.topMargin - 24)
                spacing: 18

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Search"
                        color: searchTheme.text
                        font.pixelSize: 30
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Find your way through Argon."
                        color: searchTheme.mutedText
                        font.pixelSize: 14
                    }
                }

                Row {
                    width: parent.width
                    height: 60
                    spacing: 12

                    Rectangle {
                        id: searchBox
                        width: parent.width - 64
                        height: 60
                        radius: 15
                        color: "#A6292929"
                        border.width: 1
                        border.color: searchInput.activeFocus ? searchTheme.accent : "#55FFFFFF"

                        Text {
                            x: 19
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⌕"
                            color: searchTheme.mutedText
                            font.pixelSize: 28
                        }

                        TextField {
                            id: searchInput
                            anchors.left: parent.left
                            anchors.leftMargin: 55
                            anchors.right: clearButton.left
                            anchors.rightMargin: 5
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            placeholderText: "Search anything..."
                            color: searchTheme.text
                            placeholderTextColor: "#898989"
                            font.pixelSize: 16
                            selectByMouse: true
                            verticalAlignment: TextInput.AlignVCenter
                            background: Item {}

                            onTextChanged: {
                                searchPlaceholder.query = text
                                if (text.trim().length === 0) {
                                    searchDebounce.stop()
                                    searchService.startNameSearch("")
                                    searchPlaceholder.results = []
                                    searchPlaceholder.hasMoreResults = false
                                    searchPlaceholder.currentPage = 0
                                    searchPlaceholder.searchPending = false
                                } else {
                                    searchPlaceholder.results = []
                                    searchPlaceholder.hasMoreResults = false
                                    searchPlaceholder.currentPage = 0
                                    searchPlaceholder.searchPending = true
                                    searchDebounce.restart()
                                }
                            }

                            onAccepted: {
                                searchDebounce.stop()
                                searchPlaceholder.performSearch(text)
                            }
                        }

                        Rectangle {
                            id: clearButton
                            width: 34
                            height: 34
                            anchors.right: parent.right
                            anchors.rightMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 8
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: searchTheme.mutedText
                                font.pixelSize: 20
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.clear()
                                    searchInput.forceActiveFocus()
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: argonExplorerButton
                        width: 52
                        height: 52
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 13
                        color: "transparent"
                        border.width: 1
                        border.color: "#33FFFFFF"

                        Item {
                            anchors.centerIn: parent
                            width: 22
                            height: 19

                            Rectangle {
                                x: 2
                                y: 5
                                width: 18
                                height: 12
                                radius: 2
                                color: "transparent"
                                border.color: searchTheme.text
                                border.width: 1.4
                            }

                            Rectangle {
                                x: 3
                                y: 2
                                width: 8
                                height: 5
                                radius: 1
                                color: "transparent"
                                border.color: searchTheme.text
                                border.width: 1.3
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.openArgonExplorer()
                        }
                    }
                }

                Item {
                    id: searchResultsContainer
                    width: parent.width
                    height: visible
                            ? Math.max(160, searchContentColumn.height - y)
                            : 0
                    visible: searchPlaceholder.query.trim().length > 0

                    Rectangle {
                        id: searchResultsPanel
                        x: 0
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: searchResultsContainer.width
                        radius: 14

                        Behavior on x {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Behavior on width {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                    color: "#12FFFFFF"
                    border.color: "#42FFFFFF"
                    border.width: 1
                    clip: true

                    Behavior on color { ColorAnimation { duration: 130 } }
                    Behavior on border.color { ColorAnimation { duration: 130 } }

                    Text {
                        anchors.centerIn: parent
                        visible: searchPlaceholder.results.length === 0
                                 && !searchPlaceholder.searchPending
                        text: "No results found"
                        color: searchTheme.mutedText
                        font.pixelSize: 13
                    }

                    ListView {
                        id: searchResultsList
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: paginationControls.top
                        anchors.margins: 8
                        anchors.bottomMargin: (searchPlaceholder.hasMoreResults
                                              || searchPlaceholder.results.length > searchPlaceholder.resultsPerPage) ? 4 : 0
                        visible: searchPlaceholder.results.length > 0
                        clip: true
                        model: searchPlaceholder.pageResults
                        spacing: 6

                        delegate: Rectangle {
                            required property string name
                            required property string path
                            required property string fileUrl
                            property string fileExtension: {
                                var dot = name.lastIndexOf(".")
                                return dot > 0 ? name.substring(dot + 1).toLowerCase() : ""
                            }
                            property string displayName: {
                                var dot = name.lastIndexOf(".")
                                return dot > 0 ? name.substring(0, dot) : name
                            }
                            id: searchResultCard
                            width: searchResultsList.width
                            height: 56
                            radius: 10
                            opacity: 1
                            color: resultHover.containsMouse ? "#1AFFFFFF" : "#0CFFFFFF"
                            border.color: resultHover.containsMouse ? "#72FFFFFF" : "#42FFFFFF"
                            border.width: 1
                            antialiasing: true

                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: resultHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally(fileUrl)
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.right: fileTypeLabel.left
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: displayName
                                color: searchTheme.text
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                id: fileTypeLabel
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                visible: fileExtension === "pdf"
                                         || fileExtension === "doc"
                                         || fileExtension === "docx"
                                text: fileExtension.toUpperCase()
                                color: fileExtension === "pdf" ? "#E7A0A0" : "#8CBFFF"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Row {
                        id: paginationControls
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 44
                        visible: searchPlaceholder.hasMoreResults
                                 || searchPlaceholder.results.length > searchPlaceholder.resultsPerPage
                        spacing: 12

                        Item {
                            width: parent.width
                            height: parent.height

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                Rectangle {
                                    width: 92
                                    height: 30
                                    radius: 7
                                    color: previousPageMouse.containsMouse && searchPlaceholder.currentPage > 0
                                           ? searchTheme.surfaceRaised : "transparent"
                                    border.color: searchTheme.border
                                    opacity: searchPlaceholder.currentPage > 0 ? 1 : 0.4

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Previous"
                                        color: searchTheme.text
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: previousPageMouse
                                        anchors.fill: parent
                                        enabled: searchPlaceholder.currentPage > 0
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            searchPlaceholder.currentPage--
                                            searchResultsList.contentY = 0
                                        }
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (searchPlaceholder.currentPage + 1)
                                          + " / " + (searchPlaceholder.hasMoreResults
                                                     ? "…"
                                                     : Math.max(1, searchPlaceholder.loadedPageCount))
                                    color: searchTheme.mutedText
                                    font.pixelSize: 11
                                }

                                Rectangle {
                                    width: 72
                                    height: 30
                                    radius: 7
                                    color: nextPageMouse.containsMouse ? searchTheme.surfaceRaised : "transparent"
                                    border.color: searchTheme.border
                                    opacity: (searchPlaceholder.currentPage
                                              < searchPlaceholder.loadedPageCount - 1
                                              || searchPlaceholder.hasMoreResults) ? 1 : 0.4

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Next"
                                        color: searchTheme.text
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: nextPageMouse
                                        anchors.fill: parent
                                        enabled: searchPlaceholder.currentPage
                                                     < searchPlaceholder.loadedPageCount - 1
                                                 || searchPlaceholder.hasMoreResults
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (searchPlaceholder.currentPage
                                                    < searchPlaceholder.loadedPageCount - 1) {
                                                // Revisit a page already fetched; do not query again.
                                                searchPlaceholder.currentPage++
                                            } else if (searchPlaceholder.hasMoreResults) {
                                                // Fetch only the next batch when the user requests it.
                                                var nextBatch = searchService.nextNameSearchPage()
                                                var batchResults = nextBatch.results || []
                                                if (batchResults.length > 0) {
                                                    searchPlaceholder.results =
                                                        searchPlaceholder.results.concat(batchResults)
                                                    searchPlaceholder.hasMoreResults =
                                                        nextBatch.hasMore === true
                                                    searchPlaceholder.currentPage++
                                                } else {
                                                    searchPlaceholder.hasMoreResults = false
                                                }
                                            }
                                            searchResultsList.contentY = 0
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                }
            }

        }
    }

    Component {
        id: timerPage
        TimerPage {
            controller: timerControllerInstance
            lightMode: window.lightMode
            accentColor: window.accentColor
            onPageSelected: function(pageName) {
                window.activePage = pageName
                sideBar.bannerOpen = false
            }
        }
    }
    Dialog {
        id: updaterInstallDialog
        title: "Update Argon Updater"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Cancel | Dialog.Ok
        width: 360

        contentItem: Text {
            text: "Update Argon Updater to version " + updaterStatusService.latestVersion + "?"
            color: theme.text
            wrapMode: Text.WordWrap
            font.pixelSize: 13
        }

        onAccepted: updaterStatusService.installUpdate()
    }

    Connections {
        target: releaseMetadataService
        function onStateChanged() {
            if (!window.appUpdatePromptShown
                    && releaseMetadataService.checkSucceeded
                    && releaseMetadataService.updateAvailable) {
                window.appUpdatePromptShown = true
                appUpdateDialog.open()
            }
        }
    }

    Connections {
        target: appUpdateService
        function onStateChanged() {
            if (releaseMetadataService.checkSucceeded
                    && releaseMetadataService.updateAvailable
                    && (appUpdateService.downloaded
                        || appUpdateService.state === "failed")) {
                appUpdateDialog.open()
            }
        }
    }

    Dialog {
        id: appUpdateDialog
        modal: true
        focus: true
        width: 460
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 0

        background: Rectangle {
            radius: 20
            color: theme.surfaceRaised
            border.color: theme.accent
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 106
                radius: 20
                color: theme.window
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 3
                    color: theme.accent
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14
                    Rectangle {
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 54
                        radius: 16
                        color: "#24FFFFFF"
                        border.color: theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: "↻"
                            color: theme.accent
                            font.pixelSize: 32
                            font.weight: Font.DemiBold
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: appUpdateService.downloading ? "Updating Argon"
                                  : (appUpdateService.downloaded
                                     && appUpdateService.targetVersion === releaseMetadataService.latestVersion
                                     ? "Ready to install"
                                  : (appUpdateService.installing ? "Applying update"
                                  : (appUpdateService.state === "failed" ? "Update needs attention" : "A new Argon is ready")))
                            color: theme.text
                            font.pixelSize: 21
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "ARGON  •  VERSION " + (releaseMetadataService.latestVersion || appUpdateService.targetVersion)
                            color: theme.accent
                            font.pixelSize: 10
                            font.letterSpacing: 1.2
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 22
                spacing: 15

                Text {
                    Layout.fillWidth: true
                    text: appUpdateService.downloading
                          ? appUpdateService.status
                          : (appUpdateService.downloaded
                             && appUpdateService.targetVersion === releaseMetadataService.latestVersion
                             ? "Argon " + appUpdateService.targetVersion + " has been downloaded and verified. Install it now?"
                          : (appUpdateService.installing
                             ? "Argon will restart automatically after the update is applied."
                          : (appUpdateService.state === "failed"
                             ? (appUpdateService.error.length > 0 ? appUpdateService.error : appUpdateService.status)
                             : "Version " + releaseMetadataService.latestVersion + " is available. Download and verify it securely?")))
                    color: theme.mutedText
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    visible: appUpdateService.downloading || appUpdateService.installing
                    ProgressBar {
                        id: appUpdateProgress
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: appUpdateService.progress
                        indeterminate: appUpdateService.installing
                        background: Rectangle {
                            implicitHeight: 9
                            radius: 5
                            color: theme.border
                        }
                        contentItem: Item {
                            implicitHeight: 9
                            Rectangle {
                                width: appUpdateProgress.indeterminate ? parent.width * 0.34 : parent.width * appUpdateProgress.visualPosition
                                height: parent.height
                                radius: 5
                                color: theme.accent
                                Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: appUpdateService.installing ? "Verifying the new version…"
                              : appUpdateService.progress + "% complete"
                        color: theme.mutedText
                        font.pixelSize: 11
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 9
                    Item { Layout.fillWidth: true }
                    Button {
                        visible: !appUpdateService.downloading && !appUpdateService.installing
                        text: "Not now"
                        onClicked: appUpdateDialog.close()
                        background: Rectangle {
                            radius: 10
                            color: parent.hovered ? theme.border : "transparent"
                            border.color: theme.border
                        }
                        contentItem: Text {
                            text: parent.text
                            color: theme.text
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        visible: releaseMetadataService.updateAvailable
                                 && (!appUpdateService.downloaded || appUpdateService.targetVersion !== releaseMetadataService.latestVersion)
                                 && !appUpdateService.downloading && !appUpdateService.installing
                        text: appUpdateService.state === "failed" ? "Try again" : "Download update"
                        onClicked: appUpdateService.downloadUpdate(releaseMetadataService.latestVersion)
                        background: Rectangle { radius: 10; color: parent.enabled ? (parent.hovered ? Qt.darker(theme.accent, 1.1) : theme.accent) : theme.border }
                        contentItem: Text {
                            text: parent.text
                            color: theme.accentText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        visible: appUpdateService.downloaded && appUpdateService.targetVersion === releaseMetadataService.latestVersion
                        text: "Install update"
                        onClicked: {
                            // Persist in-memory preferences before handing control to
                            // the external updater, which will close this process.
                            window.savePersistentSettings()
                            timerControllerInstance.persistElapsedState()
                            appUpdateService.installUpdate()
                        }
                        background: Rectangle { radius: 10; color: parent.hovered ? Qt.darker(theme.accent, 1.1) : theme.accent }
                        contentItem: Text {
                            text: parent.text
                            color: theme.accentText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: updateResultDialog
        modal: true
        focus: true
        width: 420
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 22
        background: Rectangle {
            radius: 18
            color: theme.surfaceRaised
            border.color: appUpdateService.state === "installed" ? "#36B56B" : "#E34B4B"
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: 13
            Text {
                Layout.fillWidth: true
                text: appUpdateService.state === "installed" ? "Argon is up to date." : "The update couldn't finish."
                color: theme.text
                font.pixelSize: 21
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: appUpdateService.state === "installed"
                      ? "Thank you for updating to Argon " + (appUpdateService.targetVersion || releaseMetadataService.currentVersion) + ". You're all set."
                      : (appUpdateService.error.length > 0 ? appUpdateService.error : appUpdateService.status)
                color: theme.mutedText
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: "Continue"
                    onClicked: updateResultDialog.close()
                    background: Rectangle { radius: 10; color: theme.accent }
                    contentItem: Text {
                        text: parent.text
                        color: theme.accentText
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Connections {
        target: appUpdateService
        function onStateChanged() {
            if (appUpdateService.state === "installed" || appUpdateService.state === "failed")
                updateResultDialog.open()
        }
    }

}
