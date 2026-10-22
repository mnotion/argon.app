import QtQuick

QtObject {
    property bool lightMode: false
    property color accent: "#8CBFFF"

    readonly property color window: lightMode ? "#F3F5F8" : "#202020"
    readonly property color surface: lightMode ? "#FFFFFF" : "#292929"
    readonly property color surfaceRaised: lightMode ? "#FBFCFE" : "#383838"
    readonly property color border: lightMode ? "#D8DDE5" : "#454545"
    readonly property color text: lightMode ? "#20242A" : "#f2f3f5"
    readonly property color mutedText: lightMode ? "#667080" : "#b8b8b8"
    readonly property color titleBar: lightMode ? "#E9EDF3" : "#252525"
    readonly property color accentText: (accent.r * 0.299 + accent.g * 0.587 + accent.b * 0.114) > 0.62
                                        ? "#202020" : "#FFFFFF"
    readonly property int radiusSmall: 8
    readonly property int radiusMedium: 12
    readonly property int sidebarWidth: 228
    readonly property int topBarHeight: 64
}
