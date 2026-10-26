import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../account"

Item {
    id: root
        property var appWindow: null
        property var themePalette: null
        anchors.fill: parent
        z: 900
        visible: root.appWindow.accountSectionOpen
        enabled: visible

        function clearSensitiveInputs() {
            signupView.clearSensitiveInputs()
            loginView.clearSensitiveInputs()
            recoveryView.clearSensitiveInputs()
        }

        function resetUitAcknowledgement() {
            uitView.resetAcknowledgement()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, root.themePalette.lightMode ? 0.35 : 0.62)
        }

        Rectangle {
            id: accountSectionCard
            width: Math.min(600, parent.width - 48)
            height: Math.min(720, parent.height - 48)
            anchors.centerIn: parent
            radius: 20
            color: Qt.rgba(root.themePalette.surface.r, root.themePalette.surface.g, root.themePalette.surface.b, 0.98)
            border.color: root.themePalette.border
            border.width: 1
            clip: true

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 3
                color: root.themePalette.accent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    Button {
                        id: accountBackButton
                        text: "← Back"
                        visible: root.appWindow.accountMode !== "login"
                        onClicked: {
                            root.appWindow.accountSectionOpen = false
                            root.appWindow.profileOpen = true
                            root.appWindow.accountUiMessage = ""
                        }
                        background: Rectangle {
                            radius: 9
                            color: accountBackButton.hovered ? root.themePalette.surfaceRaised : "transparent"
                            border.color: accountBackButton.hovered ? root.themePalette.border : "transparent"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: accountBackButton.text
                            color: root.themePalette.mutedText
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: "ARGON ACCOUNT"
                            color: root.themePalette.accent
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.appWindow.accountMode === "signup-username" || root.appWindow.accountMode === "signup-password"
                                  ? "Create your account"
                                  : root.appWindow.accountMode === "uit" ? "Save your recovery token"
                                  : root.appWindow.accountMode === "recover" ? "Recover your account"
                                  : root.appWindow.accountMode === "plans" ? "Argon plans"
                                  : root.appWindow.accountMode === "settings" ? "Account settings"
                                  : "Welcome back"
                            color: root.themePalette.text
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                    Button {
                        id: accountCloseButton
                        text: "×"
                        onClicked: {
                            root.appWindow.accountSectionOpen = false
                            root.appWindow.profileOpen = true
                        }
                        background: Rectangle {
                            radius: 9
                            color: accountCloseButton.hovered ? root.themePalette.surfaceRaised : "transparent"
                            border.color: accountCloseButton.hovered ? root.themePalette.border : "transparent"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: accountCloseButton.text
                            color: root.themePalette.mutedText
                            font.pixelSize: 22
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.themePalette.border
                    opacity: 0.7
                }

                ScrollView {
                    id: accountBodyScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    ColumnLayout {
                        width: accountBodyScroll.availableWidth
                        spacing: 14

                        SignupView {
                            id: signupView
                            Layout.fillWidth: true
                            hostWindow: root.appWindow
                            themePalette: root.themePalette
                        }



                        UitView {
                            id: uitView
                            Layout.fillWidth: true
                            hostWindow: root.appWindow
                            themePalette: root.themePalette
                        }

                        LoginView {
                            id: loginView
                            Layout.fillWidth: true
                            hostWindow: root.appWindow
                            themePalette: root.themePalette
                        }

                        RecoveryView {
                            id: recoveryView
                            Layout.fillWidth: true
                            hostWindow: root.appWindow
                            themePalette: root.themePalette
                        }

                        PlansView {
                            Layout.fillWidth: true
                            hostWindow: root.appWindow
                            themePalette: root.themePalette
                        }

                        AccountSettingsView {
                            Layout.fillWidth: true
                            hostWindow: root.appWindow
                            themePalette: root.themePalette
                        }

                        Rectangle {
                            id: accountInfoMessageBox
                            Layout.fillWidth: true
                            visible: root.appWindow.accountUiMessage.length > 0
                            implicitHeight: accountInfoMessage.implicitHeight + 24
                            radius: 10
                            color: Qt.rgba(root.themePalette.accent.r, root.themePalette.accent.g, root.themePalette.accent.b, 0.10)
                            border.color: Qt.rgba(root.themePalette.accent.r, root.themePalette.accent.g, root.themePalette.accent.b, 0.28)
                            Text {
                                id: accountInfoMessage
                                anchors.fill: parent
                                anchors.margins: 12
                                text: root.appWindow.accountUiMessage
                                color: root.themePalette.accent
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }
                        Rectangle {
                            id: accountErrorMessageBox
                            Layout.fillWidth: true
                            visible: accountService.errorMessage.length > 0
                            implicitHeight: accountErrorMessage.implicitHeight + 24
                            radius: 10
                            color: Qt.rgba(0.85, 0.20, 0.20, 0.10)
                            border.color: Qt.rgba(0.85, 0.35, 0.35, 0.30)
                            Text {
                                id: accountErrorMessage
                                anchors.fill: parent
                                anchors.margins: 12
                                text: accountService.errorMessage
                                color: "#D95D5D"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
}
