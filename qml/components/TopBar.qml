import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../themes"

Rectangle {
    id: root
    property string pageTitle: "Home"
    signal newNoteRequested()
    Theme { id: theme }
    height: theme.topBarHeight
    color: theme.window
    border.color: theme.border
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 16

        Column {
            Layout.alignment: Qt.AlignVCenter
            spacing: 3
            Text { text: root.pageTitle; color: theme.text; font.pixelSize: 21; font.bold: true }
            Text { text: "Your workspace"; color: theme.mutedText; font.pixelSize: 11 }
        }

        Item { Layout.fillWidth: true }
    }
}
