import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../themes"

Item {
    id: root
    Theme { id: theme }

    Rectangle { anchors.fill: parent; color: theme.window }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: 22
        anchors.bottomMargin: 22
        spacing: 0

        Text {
            text: "Resources"
            color: theme.text
            font.pixelSize: 25
            font.weight: Font.DemiBold
        }

        Item { Layout.fillHeight: true }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 520
            Layout.fillWidth: true
            spacing: 16

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "▤"
                color: theme.accent
                font.pixelSize: 42
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Your resources"
                color: theme.text
                font.pixelSize: 20
                font.weight: Font.Medium
            }

            Text {
                Layout.fillWidth: true
                text: "Keep useful links and files here."
                color: theme.mutedText
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            TextField {
                id: resourceInput
                Layout.fillWidth: true
                placeholderText: "Paste a link or enter a resource name"
                color: theme.text
                placeholderTextColor: theme.mutedText
                background: Rectangle {
                    radius: 10
                    color: theme.surface
                    border.color: resourceInput.activeFocus ? theme.accent : theme.border
                }
            }

            Button {
                Layout.alignment: Qt.AlignHCenter
                text: "Add resource"
                implicitWidth: 150
                implicitHeight: 42
                contentItem: Text {
                    text: parent.text
                    color: theme.accentText
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { radius: 10; color: theme.accent }
                onClicked: resourceInput.clear()
            }
        }

        Item { Layout.fillHeight: true }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "No resources yet"
            color: theme.mutedText
            font.pixelSize: 12
        }
    }
}
