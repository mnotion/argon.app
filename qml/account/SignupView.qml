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
        signupPasswordInput.clear()
    }

                            ColumnLayout {
                            Layout.fillWidth: true
                            visible: hostWindow.accountMode === "signup-username"
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                text: "Create your username"
                                color: themePalette.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Use 6–14 visible characters. Spaces and invisible/control characters are not allowed. Usernames are unique and case-insensitive."
                                color: themePalette.mutedText
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                            TextField {
                                id: signupUsernameInput
                                Layout.fillWidth: true
                                text: accountService.pendingRegistrationUsername
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
                                    border.color: signupUsernameInput.activeFocus ? themePalette.accent : themePalette.border
                                    border.width: signupUsernameInput.activeFocus ? 2 : 1
                                }
                            }
                            Button {
                                id: signupUsernameNextButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: "Next"
                                onClicked: {
                                    var candidate = signupUsernameInput.text
                                    if (candidate.length < 6 || candidate.length > 14 || /\s/.test(candidate)) {
                                        hostWindow.accountUiMessage = "Enter 6–14 visible characters without spaces or invisible characters."
                                        return
                                    }
                                    hostWindow.accountUiMessage = ""
                                    accountService.clearError()
                                    hostWindow.accountMode = "signup-password"
                                }
                                background: Rectangle {
                                    radius: 10
                                    color: signupUsernameNextButton.hovered ? Qt.lighter(themePalette.accent, 1.08) : themePalette.accent
                                }
                                contentItem: Text {
                                    text: signupUsernameNextButton.text
                                    color: themePalette.accentText
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Button {
                                id: signupToLoginButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "Already have an account? Log in"
                                flat: true
                                onClicked: { hostWindow.accountMode = "login"; hostWindow.accountUiMessage = ""; accountService.clearError() }
                                contentItem: Text {
                                    text: signupToLoginButton.text
                                    color: themePalette.accent
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                                ColumnLayout {
                            Layout.fillWidth: true
                            visible: hostWindow.accountMode === "signup-password"
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                text: "Create a password"
                                color: themePalette.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Username: " + signupUsernameInput.text
                                color: themePalette.mutedText
                                font.pixelSize: 12
                            }
                            TextField {
                                id: signupPasswordInput
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
                                    border.color: signupPasswordInput.activeFocus ? themePalette.accent : themePalette.border
                                    border.width: signupPasswordInput.activeFocus ? 2 : 1
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "8–24 characters; include an uppercase letter, a digit and at least one of @ # ! ? - _ & % $ £. Passwords are case-sensitive."
                                color: themePalette.mutedText
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                            Button {
                                id: createAccountButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: accountService.busy ? "Creating account…" : "Create account"
                                enabled: !accountService.busy
                                onClicked: accountService.createAccount(signupUsernameInput.text, signupPasswordInput.text)
                                background: Rectangle {
                                    radius: 10
                                    color: createAccountButton.enabled
                                           ? (createAccountButton.hovered ? Qt.lighter(themePalette.accent, 1.08) : themePalette.accent)
                                           : themePalette.surfaceRaised
                                }
                                contentItem: Text {
                                    text: createAccountButton.text
                                    color: createAccountButton.enabled ? themePalette.accentText : themePalette.mutedText
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Button {
                                id: signupBackButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "Back to username"
                                flat: true
                                onClicked: { hostWindow.accountMode = "signup-username"; accountService.clearError(); hostWindow.accountUiMessage = "" }
                                contentItem: Text {
                                    text: signupBackButton.text
                                    color: themePalette.mutedText
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
}
