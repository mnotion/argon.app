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
        recoveryUitInput.clear()
        recoveryPasswordInput.clear()
        recoveryConfirmInput.clear()
    }

                            ColumnLayout {
                            Layout.fillWidth: true
                            visible: hostWindow.accountMode === "recover"
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                text: "Use your username and UIT to set a new password. This will sign out existing sessions."
                                color: themePalette.mutedText
                                font.pixelSize: 14
                                wrapMode: Text.WordWrap
                            }
                            TextField {
                                id: recoveryUsernameInput
                                Layout.fillWidth: true
                                placeholderText: "Username"
                                maximumLength: 14
                                color: themePalette.text
                                selectByMouse: true
                                Layout.preferredHeight: 48
                                leftPadding: 14
                                rightPadding: 14
                                background: Rectangle {
                                    radius: 10
                                    color: themePalette.window
                                    border.color: recoveryUsernameInput.activeFocus ? themePalette.accent : themePalette.border
                                    border.width: recoveryUsernameInput.activeFocus ? 2 : 1
                                }
                            }
                            TextField {
                                id: recoveryUitInput
                                Layout.fillWidth: true
                                placeholderText: "10-character UIT"
                                maximumLength: 10
                                color: themePalette.text
                                selectByMouse: true
                                Layout.preferredHeight: 48
                                leftPadding: 14
                                rightPadding: 14
                                background: Rectangle {
                                    radius: 10
                                    color: themePalette.window
                                    border.color: recoveryUitInput.activeFocus ? themePalette.accent : themePalette.border
                                    border.width: recoveryUitInput.activeFocus ? 2 : 1
                                }
                            }
                            TextField {
                                id: recoveryPasswordInput
                                Layout.fillWidth: true
                                placeholderText: "New password"
                                maximumLength: 24
                                echoMode: TextInput.Password
                                color: themePalette.text
                                selectByMouse: true
                                Layout.preferredHeight: 48
                                leftPadding: 14
                                rightPadding: 14
                                background: Rectangle {
                                    radius: 10
                                    color: themePalette.window
                                    border.color: recoveryPasswordInput.activeFocus ? themePalette.accent : themePalette.border
                                    border.width: recoveryPasswordInput.activeFocus ? 2 : 1
                                }
                            }
                            TextField {
                                id: recoveryConfirmInput
                                Layout.fillWidth: true
                                placeholderText: "Confirm new password"
                                maximumLength: 24
                                echoMode: TextInput.Password
                                color: themePalette.text
                                selectByMouse: true
                                Layout.preferredHeight: 48
                                leftPadding: 14
                                rightPadding: 14
                                background: Rectangle {
                                    radius: 10
                                    color: themePalette.window
                                    border.color: recoveryConfirmInput.activeFocus ? themePalette.accent : themePalette.border
                                    border.width: recoveryConfirmInput.activeFocus ? 2 : 1
                                }
                            }
                            Button {
                                id: resetPasswordButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: accountService.busy ? "Recovering…" : "Reset password"
                                enabled: !accountService.busy
                                onClicked: {
                                    if (recoveryPasswordInput.text !== recoveryConfirmInput.text) {
                                        hostWindow.accountUiMessage = "The new passwords do not match."
                                        return
                                    }
                                    hostWindow.accountUiMessage = ""
                                    accountService.recoverPassword(recoveryUsernameInput.text, recoveryUitInput.text, recoveryPasswordInput.text)
                                }
                                background: Rectangle {
                                    radius: 10
                                    color: resetPasswordButton.enabled
                                           ? (resetPasswordButton.hovered ? Qt.lighter(themePalette.accent, 1.08) : themePalette.accent)
                                           : themePalette.surfaceRaised
                                }
                                contentItem: Text {
                                    text: resetPasswordButton.text
                                    color: resetPasswordButton.enabled ? themePalette.accentText : themePalette.mutedText
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Button {
                                id: recoveryBackButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "Back to login"
                                flat: true
                                onClicked: { hostWindow.accountMode = "login"; hostWindow.accountUiMessage = ""; accountService.clearError() }
                                contentItem: Text {
                                    text: recoveryBackButton.text
                                    color: themePalette.mutedText
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
}
