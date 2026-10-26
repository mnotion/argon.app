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
                            visible: hostWindow.accountMode === "plans"
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                text: "Current plan: Free"
                                color: themePalette.text
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Includes 1 GB of planned cloud storage. File synchronisation and usage tracking are not implemented yet."
                                color: themePalette.mutedText
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                            Button {
                                id: chooseStorageButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                enabled: false
                                text: "Choose storage size  ·  Coming soon"
                                background: Rectangle { radius: 10; color: themePalette.surfaceRaised; border.color: themePalette.border }
                                contentItem: Text {
                                    text: chooseStorageButton.text
                                    color: themePalette.mutedText
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Button {
                                id: expandPlanButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                enabled: false
                                text: "Expand plan options  ·  Coming soon"
                                background: Rectangle { radius: 10; color: themePalette.surfaceRaised; border.color: themePalette.border }
                                contentItem: Text {
                                    text: expandPlanButton.text
                                    color: themePalette.mutedText
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
}
