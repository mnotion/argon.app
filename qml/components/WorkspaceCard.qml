import QtQuick
import "../themes"

Rectangle {
    id: root
    property string heading: ""
    property string description: ""
    property string symbol: "•"
    property color symbolColor: "#8CBFFF"
    Theme { id: theme }
    radius: theme.radiusMedium
    color: theme.surface
    border.color: theme.border
    border.width: 1
    implicitHeight: 132
    implicitWidth: 220

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12
        Rectangle {
            width: 34; height: 34; radius: 9
            color: Qt.rgba(root.symbolColor.r, root.symbolColor.g, root.symbolColor.b, 0.14)
            Text { anchors.centerIn: parent; text: root.symbol; color: root.symbolColor; font.pixelSize: 18 }
        }
        Text { text: root.heading; color: theme.text; font.pixelSize: 15; font.bold: true }
        Text { text: root.description; color: theme.mutedText; font.pixelSize: 12; wrapMode: Text.WordWrap; width: parent.width }
    }
}
