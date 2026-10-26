import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var hostWindow: null
    property var themePalette: null
    Layout.fillWidth: true
    spacing: 14

    function clearSensitiveInputs() {
        loginPasswordInput.clear()
    }

                            ColumnLayout {
                            Layout.fillWidth: true
                            visible: hostWindow.accountMode === "login"
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                text: "Log in with your username and password."
                                color: themePalette.mutedText
                                font.pixelSize: 14
                                wrapMode: Text.WordWrap
                            }
                            TextField {
                                id: loginUsernameInput
                                Layout.fillWidth: true
                                placeholderText: "Username"
                                maximumLength: 14
                                selectByMouse: true
                                color: themePalette.text
                                Layout.preferredHeight: 48
                                leftPadding: 14
                                rightPadding: 14
                                background: Rectangle {
                                    radius: 10
                                    color: themePalette.window
                                    border.color: loginUsernameInput.activeFocus ? themePalette.accent : themePalette.border
                                    border.width: loginUsernameInput.activeFocus ? 2 : 1
                                }
                            }
                            TextField {
                                id: loginPasswordInput
                                Layout.fillWidth: true
                                placeholderText: "Password"
                                maximumLength: 24
                                echoMode: TextInput.Password
                                selectByMouse: true
                                color: themePalette.text
                                Layout.preferredHeight: 48
                                leftPadding: 14
                                rightPadding: 14
                                background: Rectangle {
                                    radius: 10
                                    color: themePalette.window
                                    border.color: loginPasswordInput.activeFocus ? themePalette.accent : themePalette.border
                                    border.width: loginPasswordInput.activeFocus ? 2 : 1
                                }
                            }
                            Button {
                                id: loginButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: accountService.busy ? "Logging in…" : "Log in"
                                enabled: !accountService.busy
                                onClicked: accountService.login(loginUsernameInput.text, loginPasswordInput.text)
                                background: Rectangle {
                                    radius: 10
                                    color: loginButton.enabled
                                           ? (loginButton.hovered ? Qt.lighter(themePalette.accent, 1.08) : themePalette.accent)
                                           : themePalette.surfaceRaised
                                }
                                contentItem: Text {
                                    text: loginButton.text
                                    color: loginButton.enabled ? themePalette.accentText : themePalette.mutedText
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Button {
                                id: forgotPasswordButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "Forgot password? Recover with UIT"
                                flat: true
                                onClicked: { hostWindow.accountMode = "recover"; hostWindow.accountUiMessage = ""; accountService.clearError() }
                                contentItem: Text {
                                    text: forgotPasswordButton.text
                                    color: themePalette.accent
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Button {
                                id: loginToSignupButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "Create a new account"
                                flat: true
                                onClicked: { hostWindow.accountMode = "signup-username"; hostWindow.accountUiMessage = ""; accountService.clearError() }
                                contentItem: Text {
                                    text: loginToSignupButton.text
                                    color: themePalette.mutedText
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
}
