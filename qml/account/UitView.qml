import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var hostWindow: null
    property var themePalette: null
    Layout.fillWidth: true
    spacing: 14

    function resetAcknowledgement() {
        uitSavedCheckbox.checked = false
    }

                            ColumnLayout {
                            Layout.fillWidth: true
                            visible: hostWindow.accountMode === "uit"
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                text: "Congratulations — your Argon account has been created."
                                color: themePalette.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Save this permanent 10-character Unique Identification Token (UIT) somewhere secure. You need it to recover your account if you lose your password. Do not share it with anyone."
                                color: themePalette.mutedText
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 72
                                radius: 12
                                color: Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.10)
                                border.color: themePalette.accent
                                border.width: 1
                                TextInput {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    text: accountService.pendingUit
                                    color: themePalette.text
                                    font.pixelSize: 22
                                    font.family: "monospace"
                                    font.weight: Font.DemiBold
                                    readOnly: true
                                    selectByMouse: true
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                }
                            }
                            Button {
                                id: copyUitButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                text: "Copy recovery token"
                                onClicked: accountService.copyPendingUit()
                                background: Rectangle {
                                    radius: 10
                                    color: copyUitButton.hovered ? themePalette.surfaceRaised : "transparent"
                                    border.color: themePalette.border
                                }
                                contentItem: Text {
                                    text: copyUitButton.text
                                    color: themePalette.text
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            CheckBox {
                                id: uitSavedCheckbox
                                Layout.fillWidth: true
                                text: "I have saved the UIT somewhere secure."
                                onCheckedChanged: hostWindow.accountUiMessage = ""
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: !accountService.loggedIn
                                text: "Log in to confirm the token was saved. Your UIT will remain on this screen."
                                color: themePalette.mutedText
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                            Button {
                                Layout.fillWidth: true
                                visible: !accountService.loggedIn
                                text: "Log in to finish setup"
                                onClicked: {
                                    uitSavedCheckbox.checked = false
                                    hostWindow.accountMode = "login"
                                    hostWindow.accountUiMessage = ""
                                }
                            }
                            Button {
                                id: continueUitButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                text: accountService.busy ? "Confirming…" : "Continue"
                                enabled: uitSavedCheckbox.checked && !accountService.busy && accountService.loggedIn
                                onClicked: accountService.acknowledgePendingUit()
                                background: Rectangle {
                                    radius: 10
                                    color: continueUitButton.enabled
                                           ? (continueUitButton.hovered ? Qt.lighter(themePalette.accent, 1.08) : themePalette.accent)
                                           : themePalette.surfaceRaised
                                }
                                contentItem: Text {
                                    text: continueUitButton.text
                                    color: continueUitButton.enabled ? themePalette.accentText : themePalette.mutedText
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
}
