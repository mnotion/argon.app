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
        anchors.bottomMargin: 18
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Doc"
                color: theme.text
                font.pixelSize: 25
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            TextField {
                id: documentName
                Layout.preferredWidth: 220
                text: "Untitled"
                color: theme.text
                font.pixelSize: 13
                horizontalAlignment: TextInput.AlignRight
                background: Item {}
            }
            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: theme.accent
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: "B"
                font.bold: true
                implicitWidth: 38
                implicitHeight: 34
                onClicked: documentEditor.font.bold = !documentEditor.font.bold
                background: Rectangle { radius: 8; color: theme.surface; border.color: theme.border }
                contentItem: Text { text: parent.text; color: theme.text; font: parent.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            Button {
                text: "I"
                font.italic: true
                implicitWidth: 38
                implicitHeight: 34
                onClicked: documentEditor.font.italic = !documentEditor.font.italic
                background: Rectangle { radius: 8; color: theme.surface; border.color: theme.border }
                contentItem: Text { text: parent.text; color: theme.text; font: parent.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            Button {
                text: "A−"
                implicitWidth: 42
                implicitHeight: 34
                onClicked: documentEditor.font.pixelSize = Math.max(10, documentEditor.font.pixelSize - 1)
                background: Rectangle { radius: 8; color: theme.surface; border.color: theme.border }
                contentItem: Text { text: parent.text; color: theme.text; font: parent.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            Button {
                text: "A+"
                implicitWidth: 42
                implicitHeight: 34
                onClicked: documentEditor.font.pixelSize = Math.min(40, documentEditor.font.pixelSize + 1)
                background: Rectangle { radius: 8; color: theme.surface; border.color: theme.border }
                contentItem: Text { text: parent.text; color: theme.text; font: parent.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Argon Doc"
                color: theme.mutedText
                font.pixelSize: 12
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: theme.surface
            border.color: theme.border
            clip: true

            TextArea {
                id: documentEditor
                anchors.fill: parent
                anchors.margins: 24
                text: ""
                placeholderText: "Start writing..."
                color: theme.text
                placeholderTextColor: theme.mutedText
                font.pixelSize: 16
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                background: Item {}
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Simple by design."
            color: theme.mutedText
            font.pixelSize: 11
        }
    }
}
