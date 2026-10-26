import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var hostWindow: null
    property var themePalette: null
    Layout.fillWidth: true
    spacing: 14

                            ColumnLayout {
                            Layout.fillWidth: true
                            visible: hostWindow.accountMode === "settings"
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                text: "Account details"
                                color: themePalette.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                            Button {
                                id: changeUsernameButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                enabled: false
                                text: "Change username  ·  Coming soon"
                                background: Rectangle { radius: 10; color: themePalette.surfaceRaised; border.color: themePalette.border }
                                contentItem: Text { text: changeUsernameButton.text; color: themePalette.mutedText; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            Button {
                                id: changePasswordButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                enabled: false
                                text: "Change password  ·  Coming soon"
                                background: Rectangle { radius: 10; color: themePalette.surfaceRaised; border.color: themePalette.border }
                                contentItem: Text { text: changePasswordButton.text; color: themePalette.mutedText; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            Button {
                                id: profilePictureButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                enabled: false
                                text: "Choose profile picture  ·  Coming soon"
                                background: Rectangle { radius: 10; color: themePalette.surfaceRaised; border.color: themePalette.border }
                                contentItem: Text { text: profilePictureButton.text; color: themePalette.mutedText; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: themePalette.border }
                            Text {
                                Layout.fillWidth: true
                                text: "Legal and privacy"
                                color: themePalette.text
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Placeholder links until Argon's legal documents are published."
                                color: themePalette.mutedText
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                            Button {
                                Layout.fillWidth: true
                                text: "Terms and privacy information"
                                onClicked: Qt.openUrlExternally("https://example.com")
                            }
                        }
}
