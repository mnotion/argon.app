import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../themes"

Item {
    id: root
    property string activePage: "Home"
    signal pageSelected(string pageName)
    signal profileRequested()
    signal settingsRequested()
    signal fullscreenRequested()
    property bool bannerOpen: false
    property bool notesHandleDimmed: false
    Theme { id: theme }

    Layout.fillWidth: true
    Layout.preferredHeight: 0
    Layout.leftMargin: 16
    Layout.rightMargin: 16
    z: 10
    clip: false

    Rectangle {
        id: banner
        x: (root.width - width) / 2
        y: root.bannerOpen ? 0 : -58
        width: Math.min(root.width - 32, 560)
        height: 58
        color: "transparent"
        border.color: "transparent"
        border.width: 0
        radius: 14
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: 14
        bottomRightRadius: 14
        clip: false
        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
        z: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 5
            anchors.bottomMargin: 5
            spacing: 5

            Repeater {
                model: [
                    { label: "Search", symbol: "⌕", revealDelay: 220 },
                    { label: "Notes", symbol: "✎", revealDelay: 120 },
                    { label: "Timer", symbol: "◷", revealDelay: 0 },
                ]

                delegate: Button {
                    id: navButton
                    required property var modelData
                    property bool revealed: false
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    opacity: revealed ? 1 : 0
                    scale: revealed ? (hovered ? 1.045 : 1) : 0.88
                    y: revealed ? 0 : 10
                    visible: root.bannerOpen || opacity > 0.01
                    onVisibleChanged: {
                        if (visible && root.bannerOpen)
                            revealTimer.restart()
                    }
                    Connections {
                        target: root
                        function onBannerOpenChanged() {
                            if (root.bannerOpen) {
                                navButton.visible = true
                                revealTimer.restart()
                            } else {
                                revealTimer.stop()
                                navButton.revealed = false
                            }
                        }
                    }
                    Timer {
                        id: revealTimer
                        interval: navButton.modelData.revealDelay
                        repeat: false
                        onTriggered: navButton.revealed = root.bannerOpen
                    }
                    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Layout.margins: 2
                    flat: true
                    onClicked: root.pageSelected(modelData.label)
                    z: hovered ? 5 : 0
                    TapHandler {
                        acceptedDevices: PointerDevice.Stylus
                        onTapped: root.pageSelected(navButton.modelData.label)
                    }
                    background: Rectangle {
                        id: navButtonBackground
                        radius: 10
                        color: root.activePage === navButton.modelData.label
                               ? (navButton.hovered ? "#E6D8BD72" : theme.accent)
                               : (navButton.hovered ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(0, 0, 0, 0.10))
                        border.width: root.activePage === navButton.modelData.label ? 0 : 1
                        border.color: navButton.hovered ? "#777777" : "#3d3d3d"
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: "#55000000"
                            shadowBlur: 0.12
                            shadowOpacity: 0.16
                            shadowVerticalOffset: 1
                        }
                    }
                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                text: navButton.modelData.symbol
                                color: root.activePage === navButton.modelData.label ? theme.accentText : theme.mutedText
                                font.pixelSize: 15
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                text: navButton.modelData.label
                                color: root.activePage === navButton.modelData.label ? theme.accentText : theme.text
                                font.pixelSize: 18
                                font.weight: Font.Medium
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: [
            { side: "left", symbol: "●", label: "Profile" },
            { side: "right", symbol: "⚙", label: "Settings" }
        ]

        delegate: Rectangle {
            id: utilityButton
            required property var modelData
            property bool shown: root.bannerOpen
            property bool movementShown: false
            readonly property int stagger: 140
            width: 44
            height: 44
            radius: 13
            x: modelData.side === "left" ? banner.x - width - 12 : banner.x + banner.width + 12
            y: (banner.height - height) / 2 + (movementShown ? -2 : -20)
            opacity: movementShown ? 1 : 0
            scale: movementShown ? 1 : 0.72
            color: utilityMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(0, 0, 0, 0.10)
            border.color: theme.border
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#55000000"
                shadowBlur: 0.12
                shadowOpacity: 0.16
                shadowVerticalOffset: 1
            }
            z: 3
            visible: root.bannerOpen || opacity > 0.01

            onShownChanged: {
                if (shown) {
                    visible = true
                    staggerTimer.restart()
                } else {
                    staggerTimer.restart()
                }
            }

            Timer {
                id: staggerTimer
                interval: utilityButton.stagger
                repeat: false
                onTriggered: utilityButton.movementShown = utilityButton.shown
            }

            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

            Image {
                anchors.centerIn: parent
                width: 25
                height: 25
                source: utilityButton.modelData.label === "Settings"
                        ? "../assets/icons/Settings/setting-icon.png" : ""
                visible: utilityButton.modelData.label === "Settings"
                fillMode: Image.PreserveAspectFit
                smooth: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    brightness: 1.0
                    colorization: 1.0
                    colorizationColor: "white"
                }
            }

            Text {
                anchors.centerIn: parent
                text: utilityButton.modelData.label === "Profile" ? utilityButton.modelData.symbol : ""
                color: theme.text
                font.pixelSize: 20
                visible: utilityButton.modelData.label === "Profile"
            }

            MouseArea {
                id: utilityMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (utilityButton.modelData.label === "Profile")
                        root.profileRequested()
                    else
                        root.settingsRequested()
                }
            }
        }
    }

    Rectangle {
        id: revealTab
        width: 64
        height: 28
        radius: 7
        color: theme.border
        x: (root.width - width) / 2
        y: banner.y + banner.height - 1
        z: 2
        opacity: root.activePage === "Notes" && !root.bannerOpen && root.notesHandleDimmed ? 0.08 : 1
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

        Timer {
            id: notesHandleIdleTimer
            interval: 2000
            repeat: false
            onTriggered: {
                if (root.activePage === "Notes" && !root.bannerOpen)
                    root.notesHandleDimmed = true
            }
        }

        Connections {
            target: root
            function onActivePageChanged() {
                notesHandleIdleTimer.stop()
                root.notesHandleDimmed = false
                if (root.activePage === "Notes" && !root.bannerOpen)
                    notesHandleIdleTimer.restart()
            }
            function onBannerOpenChanged() {
                notesHandleIdleTimer.stop()
                root.notesHandleDimmed = false
                if (root.activePage === "Notes" && !root.bannerOpen)
                    notesHandleIdleTimer.restart()
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 1
            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    width: 24
                    height: 3
                    radius: 1
                    color: theme.mutedText
                }
            }
        }

        TapHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus | PointerDevice.TouchScreen
            onTapped: {
                notesHandleIdleTimer.stop()
                root.notesHandleDimmed = false
                root.bannerOpen = !root.bannerOpen
                if (root.activePage === "Notes" && !root.bannerOpen)
                    notesHandleIdleTimer.restart()
            }
        }
    }
}
