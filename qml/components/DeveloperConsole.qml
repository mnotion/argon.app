import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root

    property color panelColor: "#303030"
    property color textColor: "#F2F3F5"
    property color mutedTextColor: "#B8B8B8"
    property color borderColor: "#454545"
    property color accentColor: "#8CBFFF"
    property color accentTextColor: "#202020"

    width: 780
    height: 540
    modal: false
    focus: true
    padding: 16
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: Overlay.overlay

    background: Rectangle {
        radius: 14
        color: root.panelColor
        border.color: root.borderColor
        border.width: 1
    }

    onOpened: editor.forceActiveFocus()

    function runScript() {
        var result = scriptService.execute(editor.text)
        var lines = []

        for (var i = 0; i < result.output.length; ++i)
            lines.push(String(result.output[i]))

        for (var j = 0; j < result.diagnostics.length; ++j) {
            var diagnostic = result.diagnostics[j]
            lines.push("ERROR [" + diagnostic.line + ":" + diagnostic.column + "] " + diagnostic.message)
        }

        if (result.success && lines.length === 0)
            lines.push("Executed successfully. No output.")
        output.text = lines.join("\n")
    }

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "Argon Script Console"
                color: root.textColor
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }

            Text {
                text: "F12"
                color: root.mutedTextColor
                font.pixelSize: 11
            }

            Button {
                text: "Close"
                onClicked: root.close()
                background: Rectangle {
                    radius: 7
                    color: parent.hovered ? root.borderColor : "transparent"
                }
                contentItem: Text {
                    text: parent.text
                    color: root.textColor
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Runs inside the current Argon process. Globals persist until you reset the session."
            color: root.mutedTextColor
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        TextArea {
            id: editor
            Layout.fillWidth: true
            Layout.preferredHeight: 250
            text: 'print("Argon " + applicationVersion());\nlet answer = 10 + 20;\nprint(answer);\n\n// Search the current Argon search index:\n// let results = search("report");\n// print(results);'
            color: root.textColor
            selectedTextColor: root.accentTextColor
            selectionColor: root.accentColor
            font.family: "Consolas"
            font.pixelSize: 12
            wrapMode: TextEdit.NoWrap
            selectByMouse: true
            background: Rectangle {
                radius: 8
                color: Qt.darker(root.panelColor, 1.12)
                border.color: root.borderColor
                border.width: 1
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                text: "Run"
                onClicked: root.runScript()
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? Qt.darker(root.accentColor, 1.08) : root.accentColor
                }
                contentItem: Text {
                    text: parent.text
                    color: root.accentTextColor
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Button {
                text: "Reset session"
                onClicked: {
                    scriptService.reset()
                    output.text = "Interpreter session reset."
                }
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? root.borderColor : "transparent"
                    border.color: root.borderColor
                }
                contentItem: Text {
                    text: parent.text
                    color: root.textColor
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Button {
                text: "Clear output"
                onClicked: output.clear()
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? root.borderColor : "transparent"
                }
                contentItem: Text {
                    text: parent.text
                    color: root.mutedTextColor
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Item { Layout.fillWidth: true }
        }

        TextArea {
            id: output
            Layout.fillWidth: true
            Layout.fillHeight: true
            readOnly: true
            selectByMouse: true
            placeholderText: "Script output and errors appear here."
            color: root.textColor
            font.family: "Consolas"
            font.pixelSize: 12
            wrapMode: TextEdit.Wrap
            background: Rectangle {
                radius: 8
                color: Qt.darker(root.panelColor, 1.12)
                border.color: root.borderColor
                border.width: 1
            }
        }
    }
}
