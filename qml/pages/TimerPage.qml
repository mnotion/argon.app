import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../themes"

Item {
    id: root
    Theme { id: theme }
    signal pageSelected(string pageName)

    property var controller: null
    property bool dailyCardExpanded: false
    property bool dailyCardSettled: false
    property bool dailyHandleSettled: false
    property bool handleExpanded: false
    property real dailyCardCloudPhase: 0
    property real dailyHandleCloudPhase: 0
    property bool calendarExpanded: false
    property bool calendarSettled: false
    property bool calendarHandleSettled: false
    property bool calendarHandleExpanded: false
    property bool calendarWaveVisible: false
    property real calendarCloudPhase: 0
    property real calendarHandleCloudPhase: 0
    property int displayedCalendarYear: new Date().getFullYear()
    property int displayedCalendarMonth: new Date().getMonth()
    property var calendarFocusedSeconds: ({})
    property string calendarTodayIsoDate: ""
    property double todayFocusedSeconds: 0
    property real calendarSwipeStartX: 0
    property real calendarSwipeStartY: 0
    property real calendarDragOffset: 0
    property int calendarCommitOffset: 0
    property bool calendarGestureDecided: false
    property bool calendarHorizontalGesture: false
    property var subjects: []
    property string selectedSubjectId: ""
    property bool subjectDialogOpen: false
    property string newSubjectName: ""
    property string newSubjectGoal: ""
    property string newSubjectColour: "#8CBFFF"
    property string subjectFormError: ""
    property var subjectColourPalette: [
        "#8CBFFF", "#81C995", "#F4C96B", "#E99AAE",
        "#B5A2F5", "#E9A16D", "#62C5C1", "#D8DDE7"
    ]
    property real timerIntroProgress: 0

    function loadSubjects() {
        var storedSubjects = appSettingsService.value("timer.subjects", [])
        subjects = storedSubjects && storedSubjects.length !== undefined
                ? storedSubjects : []
        selectedSubjectId = String(appSettingsService.value("timer.selectedSubjectId", ""))
    }

    function openSubjectDialog() {
        newSubjectName = ""
        newSubjectGoal = ""
        newSubjectColour = subjectColourPalette[0]
        subjectFormError = ""
        subjectDialogOpen = true
        Qt.callLater(function() { subjectNameInput.forceActiveFocus() })
    }

    function closeSubjectDialog() {
        subjectDialogOpen = false
        subjectFormError = ""
    }

    function addSubject() {
        var name = newSubjectName.trim()
        var goalHours = Number(newSubjectGoal)
        if (name.length === 0) {
            subjectFormError = "Enter a subject name."
            subjectNameInput.forceActiveFocus()
            return
        }
        if (newSubjectGoal.trim().length === 0 || !isFinite(goalHours) || goalHours <= 0) {
            subjectFormError = "Enter a goal greater than zero hours."
            subjectGoalInput.forceActiveFocus()
            return
        }

        var subjectId = String(new Date().getTime()) + "-" + String(subjects.length + 1)
        var newSubject = {
            "id": subjectId,
            "name": name,
            "colour": String(newSubjectColour),
            "goalHours": goalHours
        }
        var updatedSubjects = subjects.slice()
        updatedSubjects.push(newSubject)
        if (!appSettingsService.setValue("timer.subjects", updatedSubjects)) {
            subjectFormError = "The subject could not be saved. Please try again."
            return
        }

        subjects = updatedSubjects
        selectedSubjectId = subjectId
        appSettingsService.setValue("timer.selectedSubjectId", selectedSubjectId)
        subjectDialogOpen = false
        subjectFormError = ""
    }

    function selectSubject(subjectId) {
        selectedSubjectId = String(subjectId)
        if (!appSettingsService.setValue("timer.selectedSubjectId", selectedSubjectId))
            console.warn("[Timer] Could not save the selected subject.")
    }

    function orderedSubjects() {
        var ordered = subjects.slice()
        if (selectedSubjectId.length === 0)
            return ordered
        var selectedIndex = -1
        for (var i = 0; i < ordered.length; ++i) {
            if (String(ordered[i].id) === selectedSubjectId) {
                selectedIndex = i
                break
            }
        }
        if (selectedIndex > 0)
            ordered.unshift(ordered.splice(selectedIndex, 1)[0])
        return ordered
    }

    function formattedSubjectElapsed(subjectId) {
        var trackedMilliseconds = Number(controller.subjectElapsedMilliseconds[String(subjectId)] || 0)
        var totalMinutes = Math.floor(Math.max(0, trackedMilliseconds) / 60000)
        var hours = Math.floor(totalMinutes / 60)
        var minutes = totalMinutes % 60
        return (hours < 10 ? "0" : "") + hours + ":"
                + (minutes < 10 ? "0" : "") + minutes
    }

    function startSubjectTimer(subjectId) {
        var requestedId = String(subjectId)
        selectSubject(requestedId)

        if (controller.timerRunning) {
            if (String(controller.activeSubjectId) === requestedId) {
                controller.toggleTimer()
                return
            }

            // Attribute the preceding interval to the subject that was active.
            controller.tick()
            controller.activeSubjectId = requestedId
            controller.persistElapsedState()
            return
        }

        controller.activeSubjectId = requestedId
        controller.toggleTimer()
    }

    function toggleSelectedSubjectTimer() {
        if (controller.timerRunning) {
            controller.toggleTimer()
            return
        }
        if (selectedSubjectId.length > 0)
            controller.activeSubjectId = selectedSubjectId
        controller.toggleTimer()
    }

    function introProgress(delay) {
        if (timerIntroProgress <= delay)
            return 0
        return Math.min(1, (timerIntroProgress - delay) / (1 - delay))
    }

    function applyCalendarMonthOffset(offset) {
        var date = new Date(displayedCalendarYear, displayedCalendarMonth + offset, 1)
        displayedCalendarYear = date.getFullYear()
        displayedCalendarMonth = date.getMonth()
    }

    function calendarMonthDate(offset) {
        return new Date(displayedCalendarYear, displayedCalendarMonth + offset, 1)
    }

    function calendarMonthName(offset) {
        return Qt.formatDate(calendarMonthDate(offset), "MMMM")
    }

    function calendarYearText(offset) {
        return Qt.formatDate(calendarMonthDate(offset), "yyyy")
    }

    function calendarFirstWeekday(offset) {
        return calendarMonthDate(offset).getDay()
    }

    function calendarDaysInMonth(offset) {
        var date = calendarMonthDate(offset)
        return new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()
    }

    function calendarCellDay(index, offset) {
        var day = index - calendarFirstWeekday(offset) + 1
        return day >= 1 && day <= calendarDaysInMonth(offset) ? day : ""
    }

    function isToday(day, offset) {
        var now = new Date()
        var month = calendarMonthDate(offset)
        return day !== ""
                && month.getFullYear() === now.getFullYear()
                && month.getMonth() === now.getMonth()
                && Number(day) === now.getDate()
    }

    function isCurrentMonthOffset(offset) {
        var now = new Date()
        var month = calendarMonthDate(offset)
        return month.getFullYear() === now.getFullYear()
                && month.getMonth() === now.getMonth()
    }

    function calendarDateKey(date) {
        var monthNumber = date.getMonth() + 1
        var dayNumber = date.getDate()
        return date.getFullYear() + "-"
                + (monthNumber < 10 ? "0" : "") + monthNumber + "-"
                + (dayNumber < 10 ? "0" : "") + dayNumber
    }

    function calendarIsoDate(day, offset) {
        if (day === "" || day === null || day === undefined)
            return ""
        var month = calendarMonthDate(offset)
        return calendarDateKey(new Date(month.getFullYear(), month.getMonth(), Number(day)))
    }

    function formatCalendarDuration(seconds) {
        var totalMinutes = Math.floor(Math.max(0, Number(seconds) || 0) / 60)
        var hours = Math.floor(totalMinutes / 60)
        var minutes = totalMinutes % 60
        return (hours < 10 ? "0" : "") + hours + ":"
                + (minutes < 10 ? "0" : "") + minutes
    }

    function calendarCellSeconds(day, offset) {
        var key = calendarIsoDate(day, offset)
        if (key === "")
            return 0
        if (key === calendarTodayIsoDate)
            return todayFocusedSeconds
        return Number(calendarFocusedSeconds[key] || 0)
    }

    function calendarMonthTotalSeconds(offset) {
        var total = 0
        for (var day = 1; day <= calendarDaysInMonth(offset); ++day) {
            var key = calendarIsoDate(String(day), offset)
            total += Number(calendarFocusedSeconds[key] || 0)
            if (key === calendarTodayIsoDate)
                total += todayFocusedSeconds - Number(calendarFocusedSeconds[key] || 0)
        }
        return total
    }

    function calendarCellBackground(seconds, today) {
        if (today)
            return Qt.rgba(theme.accent.r * 0.20, theme.accent.g * 0.20, theme.accent.b * 0.20, 1)
        if (seconds <= 0)
            return Qt.rgba(1, 1, 1, 0.045)
        var intensity = Math.sqrt(Math.min(1, seconds / 7200))
        return Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.08 + intensity * 0.42)
    }

    function refreshCalendarData() {
        var values = {}
        for (var offset = -1; offset <= 1; ++offset) {
            var daysInMonth = calendarDaysInMonth(offset)
            for (var day = 1; day <= daysInMonth; ++day) {
                var key = calendarIsoDate(String(day), offset)
                // Keep totals for overlapping months; only read newly exposed dates.
                values[key] = calendarFocusedSeconds[key] !== undefined
                        ? calendarFocusedSeconds[key]
                        : dailyAnalyticsService.focusedSecondsForDate(key)
            }
        }
        calendarFocusedSeconds = values
        calendarTodayIsoDate = calendarDateKey(new Date())
        todayFocusedSeconds = dailyAnalyticsService.focusedSecondsForDate(calendarTodayIsoDate)
    }

    function refreshTodayCalendarData() {
        var currentDateKey = calendarDateKey(new Date())
        if (currentDateKey !== calendarTodayIsoDate) {
            refreshCalendarData()
            return
        }
        todayFocusedSeconds = dailyAnalyticsService.focusedSecondsForDate(currentDateKey)
    }

    function formattedFocusedTime() {
        var totalMinutes = Math.floor(dailyAnalyticsService.focusedSecondsToday / 60)
        if (totalMinutes < 60)
            return totalMinutes + " min"
        return Math.floor(totalMinutes / 60) + " h " + (totalMinutes % 60) + " min"
    }

    function formattedDate() {
        var date = new Date()
        var day = date.getDate()
        var suffix = "th"
        if (day % 100 < 11 || day % 100 > 13) {
            if (day % 10 === 1) suffix = "st"
            else if (day % 10 === 2) suffix = "nd"
            else if (day % 10 === 3) suffix = "rd"
        }
        return Qt.formatDate(date, "MMMM ") + day + suffix
    }

    onDailyCardExpandedChanged: {
        cardSettleTimer.stop()
        handleDelayTimer.stop()
        handleSettleTimer.stop()
        dateFadeTimer.stop()

        if (dailyCardExpanded) {
            focusedTimeText.opacity = 0
            focusedDateText.opacity = 0
            cardSettleTimer.start()
            handleDelayTimer.start()
            handleSettleTimer.start()
        } else {
            dailyCardSettled = false
            dailyHandleSettled = false
            dailyCardCloudPhase = 0
            dailyHandleCloudPhase = 0
            focusedTimeText.opacity = 0
            focusedDateText.opacity = 0
            handleExpanded = false
        }
    }

    onCalendarExpandedChanged: {
        calendarSettleTimer.stop()
        calendarHandleDelayTimer.stop()
        calendarHandleSettleTimer.stop()
        calendarWaveRevealTimer.stop()

        if (calendarExpanded) {
            calendarWaveVisible = false
            calendarSettleTimer.start()
            calendarHandleDelayTimer.start()
            calendarHandleSettleTimer.start()
        } else {
            calendarSettled = false
            calendarHandleSettled = false
            calendarCloudPhase = 0
            calendarHandleCloudPhase = 0
            calendarWaveVisible = false
            calendarHandleExpanded = false
        }
    }

    Timer {
        id: cardSettleTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (root.dailyCardExpanded) {
                root.dailyCardSettled = true
                focusedTimeText.opacity = 1
                dateFadeTimer.start()
            }
        }
    }

    Timer {
        id: calendarSettleTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (root.calendarExpanded) {
                root.calendarSettled = true
                calendarWaveRevealTimer.start()
            }
        }
    }

    // Match the daily-card handle's tiny delay before it follows the calendar.
    Timer {
        id: calendarHandleDelayTimer
        interval: 8
        repeat: false
        onTriggered: root.calendarHandleExpanded = root.calendarExpanded
    }

    Timer {
        id: calendarHandleSettleTimer
        interval: 908
        repeat: false
        onTriggered: {
            if (root.calendarExpanded)
                root.calendarHandleSettled = true
        }
    }

    Timer {
        id: calendarWaveRevealTimer
        interval: 90
        repeat: false
        onTriggered: {
            if (root.calendarExpanded)
                root.calendarWaveVisible = true
        }
    }

    SequentialAnimation {
        running: root.calendarSettled
        loops: Animation.Infinite
        NumberAnimation {
            target: root
            property: "calendarCloudPhase"
            to: 1
            duration: 3000
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "calendarCloudPhase"
            to: 0
            duration: 3000
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation {
        running: root.calendarHandleSettled
        loops: Animation.Infinite
        NumberAnimation {
            target: root
            property: "calendarHandleCloudPhase"
            to: 1
            duration: 3000
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "calendarHandleCloudPhase"
            to: 0
            duration: 3000
            easing.type: Easing.InOutSine
        }
    }

    // Just over one frame at 180 Hz: the handle trails the card very slightly.
    Timer {
        id: handleDelayTimer
        interval: 8
        repeat: false
        onTriggered: root.handleExpanded = root.dailyCardExpanded
    }

    Timer {
        id: handleSettleTimer
        interval: 908
        repeat: false
        onTriggered: {
            if (root.dailyCardExpanded)
                root.dailyHandleSettled = true
        }
    }

    // Let the time appear first, then reveal the date a beat later.
    Timer {
        id: dateFadeTimer
        interval: 115
        repeat: false
        onTriggered: {
            if (root.dailyCardExpanded)
                focusedDateText.opacity = 1
        }
    }

    SequentialAnimation {
        running: root.dailyCardSettled
        loops: Animation.Infinite
        NumberAnimation {
            target: root
            property: "dailyCardCloudPhase"
            to: 1
            duration: 3000
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "dailyCardCloudPhase"
            to: 0
            duration: 3000
            easing.type: Easing.InOutSine
        }
    }

    SequentialAnimation {
        running: root.dailyHandleSettled
        loops: Animation.Infinite
        NumberAnimation {
            target: root
            property: "dailyHandleCloudPhase"
            to: 1
            duration: 3000
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "dailyHandleCloudPhase"
            to: 0
            duration: 3000
            easing.type: Easing.InOutSine
        }
    }

    NumberAnimation {
        id: timerPageEntrance
        target: root
        property: "timerIntroProgress"
        from: 0
        to: 1
        duration: 920
        easing.type: Easing.OutCubic
    }

    Component.onCompleted: {
        dailyAnalyticsService.refreshToday()
        refreshCalendarData()
        loadSubjects()
        timerIntroProgress = 0
        timerPageEntrance.start()
    }

    Connections {
        target: dailyAnalyticsService
        function onDailyStatsChanged() {
            root.refreshTodayCalendarData()
        }
    }

    Item {
        id: pageContent
        anchors.fill: parent
        layer.enabled: root.subjectDialogOpen
        layer.effect: MultiEffect {
            blurEnabled: root.subjectDialogOpen
            blur: root.subjectDialogOpen ? 0.9 : 0
            blurMax: 32
        }

        Rectangle {
            anchors.fill: parent
            color: theme.window
        }

    // Compact subject list, placed higher with the Add control centered beneath it.
    Rectangle {
        id: subjectsPanel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 82
        width: Math.min(560, parent.width - 80)
        height: Math.min(260, Math.max(196, parent.height * 0.36))
        radius: 18
        color: theme.surface
        border.color: theme.border
        border.width: 1
        z: 2

        RowLayout {
            id: subjectsHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 12
            height: 24
            spacing: 8

            Text {
                text: "Subjects"
                color: theme.mutedText
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1.0
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: String(root.subjects.length)
                color: theme.mutedText
                font.pixelSize: 10
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }
        }

        Flickable {
            id: subjectCardsViewport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: subjectsHeader.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 8
            anchors.bottomMargin: 10
            clip: true
            contentWidth: width
            contentHeight: subjectRowsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: subjectRowsColumn
                width: subjectCardsViewport.width
                spacing: 7

                Repeater {
                    model: root.orderedSubjects()
                    delegate: Rectangle {
                        required property var modelData
                        readonly property var subjectData: modelData
                        readonly property color subjectAccent: String(subjectData.colour)
                        readonly property bool isSelected: root.selectedSubjectId === String(subjectData.id)
                        width: subjectRowsColumn.width
                        height: 44
                        radius: 10
                        color: isSelected
                               ? Qt.rgba(subjectAccent.r, subjectAccent.g, subjectAccent.b, 0.12)
                               : Qt.rgba(1, 1, 1, 0.025)
                        border.width: isSelected ? 1.5 : 1
                        border.color: isSelected ? String(subjectData.colour) : theme.border
                        clip: true

                        // A single accent rail replaces the rounded card's left border.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 4
                            color: String(subjectData.colour)
                            z: 2
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: subjectElapsedBadge.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 13
                            anchors.rightMargin: 12
                            text: String(subjectData.name || "Subject")
                            color: theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: subjectTimerControl.left
                            anchors.rightMargin: 4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectSubject(subjectData.id)
                        }

                        Text {
                            id: subjectElapsedBadge
                            anchors.right: subjectTimerControl.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.formattedSubjectElapsed(subjectData.id)
                            color: isSelected ? String(subjectData.colour) : theme.mutedText
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Rectangle {
                            id: subjectTimerControl
                            anchors.right: parent.right
                            anchors.rightMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            width: 31
                            height: 31
                            radius: 8
                            z: 2
                            color: subjectTimerMouse.containsMouse
                                   ? Qt.rgba(subjectAccent.r, subjectAccent.g, subjectAccent.b, 0.22)
                                   : Qt.rgba(1, 1, 1, 0.035)
                            border.color: controller.timerRunning
                                          && String(controller.activeSubjectId) === String(subjectData.id)
                                          ? String(subjectData.colour) : theme.border

                            Text {
                                anchors.centerIn: parent
                                text: controller.timerRunning
                                      && String(controller.activeSubjectId) === String(subjectData.id)
                                      ? "Ⅱ" : "▶"
                                color: String(subjectData.colour)
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: subjectTimerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.startSubjectTimer(subjectData.id)
                            }

                            ToolTip.visible: subjectTimerMouse.containsMouse
                            ToolTip.text: controller.timerRunning
                                          && String(controller.activeSubjectId) === String(subjectData.id)
                                          ? "Pause this subject" : "Start timer on this subject"
                            ToolTip.delay: 350
                        }
                    }
                }
            }
        }
    }

    Row {
        id: addSubjectButton
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: subjectsPanel.bottom
        anchors.topMargin: 8
        spacing: 9
        z: 3

        Rectangle {
            width: 36
            height: 34
            radius: 9
            color: addSubjectMouse.containsMouse
                   ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.17)
                   : theme.surface
            border.color: addSubjectMouse.containsMouse ? theme.accent : theme.border

            Text {
                anchors.centerIn: parent
                text: "+"
                color: theme.accent
                font.pixelSize: 23
                font.weight: Font.Light
            }

            MouseArea {
                id: addSubjectMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSubjectDialog()
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Add subject"
            color: addSubjectMouse.containsMouse ? theme.accent : theme.mutedText
            font.pixelSize: 12
        }
    }

    // Calendar swipe follows the pointer and previews adjacent months before release.
    Rectangle {
        id: monthlyCalendarCard
        x: root.calendarExpanded ? 22 : -width + 24
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -8
            + (root.calendarSettled
               ? Math.sin(root.calendarCloudPhase * 2 * Math.PI) * 3 : 0)
        width: 300
        height: 360
        radius: 16
        color: Qt.lighter(theme.surface, 1.0 + 0.11 * root.calendarCloudPhase)
        border.color: Qt.lighter(theme.border, 1.0 + 0.06 * root.calendarCloudPhase)
        border.width: 1
        clip: true
        z: 4
        opacity: root.introProgress(0.02)
        scale: root.calendarExpanded ? 1.02 : 0.96

        transform: [
            Scale {
                origin.x: monthlyCalendarCard.width / 2
                origin.y: monthlyCalendarCard.height / 2
                xScale: 0.96 + 0.04 * root.introProgress(0.02)
                yScale: 0.96 + 0.04 * root.introProgress(0.02)
            },
            Translate {
                y: (1 - root.introProgress(0.02)) * 13
            }
        ]

        Behavior on x {
            NumberAnimation {
                duration: 900
                easing.type: Easing.OutExpo
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 900
                easing.type: Easing.OutExpo
            }
        }

        Item {
            id: calendarViewport
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 24
            anchors.bottomMargin: 12
            clip: true

            Row {
                id: calendarPagesRow
                x: -calendarViewport.width + root.calendarDragOffset
                y: 0
                width: calendarViewport.width * 3
                height: calendarViewport.height
                spacing: 0

                Loader {
                    width: calendarViewport.width
                    height: calendarViewport.height
                    sourceComponent: calendarMonthPageComponent
                    onLoaded: item.monthOffset = -1
                }

                Loader {
                    width: calendarViewport.width
                    height: calendarViewport.height
                    sourceComponent: calendarMonthPageComponent
                    onLoaded: item.monthOffset = 0
                }

                Loader {
                    width: calendarViewport.width
                    height: calendarViewport.height
                    sourceComponent: calendarMonthPageComponent
                    onLoaded: item.monthOffset = 1
                }
            }
        }

        Component {
            id: calendarMonthPageComponent

            Item {
                id: monthPage
                property int monthOffset: 0
                width: calendarViewport.width
                height: calendarViewport.height

                Column {
                    anchors.fill: parent
                    spacing: 8

                    Row {
                        id: calendarMonthHeading
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 5
                        height: 24
                        opacity: root.calendarWaveVisible ? 1 : 0
                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: 0 }
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                        }
                        transform: Translate {
                            y: root.calendarWaveVisible ? 0 : 7
                            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }

                        Item {
                            width: monthNameText.implicitWidth + 28
                            height: 24

                            Text {
                                id: monthNameText
                                anchors.centerIn: parent
                                text: root.calendarMonthName(monthPage.monthOffset)
                                color: root.isCurrentMonthOffset(monthPage.monthOffset)
                                       ? theme.accent : theme.text
                                font.pixelSize: 18
                                font.weight: root.isCurrentMonthOffset(monthPage.monthOffset)
                                             ? Font.DemiBold : Font.Medium
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.calendarYearText(monthPage.monthOffset)
                            color: theme.mutedText
                            font.pixelSize: 16
                            font.weight: Font.Normal
                        }
                    }

                    Text {
                        id: calendarMonthTotalLabel
                        width: parent.width
                        height: 13
                        opacity: root.calendarWaveVisible ? 1 : 0
                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: 55 }
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                        }
                        transform: Translate {
                            y: root.calendarWaveVisible ? 0 : 7
                            Behavior on y { SequentialAnimation {
                                PauseAnimation { duration: 55 }
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            } }
                        }
                        text: "MONTHLY FOCUS  " + root.formatCalendarDuration(
                                  root.calendarMonthTotalSeconds(monthPage.monthOffset))
                        color: theme.mutedText
                        font.pixelSize: 9
                        font.letterSpacing: 0.6
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    Grid {
                        id: calendarWeekdayHeader
                        width: parent.width
                        columns: 7
                        spacing: 0
                        opacity: root.calendarWaveVisible ? 1 : 0
                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: 110 }
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                        }
                        transform: Translate {
                            y: root.calendarWaveVisible ? 0 : 7
                            Behavior on y {
                                SequentialAnimation {
                                    PauseAnimation { duration: 110 }
                                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Repeater {
                            model: ["S", "M", "T", "W", "T", "F", "S"]
                            delegate: Text {
                                required property string modelData
                                width: calendarViewport.width / 7
                                height: 22
                                text: modelData
                                color: theme.mutedText
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 7
                        rowSpacing: 3
                        columnSpacing: 0

                        Repeater {
                            model: 42
                            delegate: Item {
                                id: calendarDayCell
                                required property int index
                                width: calendarViewport.width / 7
                                height: 36

                                property string dayNumber: root.calendarCellDay(index, monthPage.monthOffset)
                                property string isoDate: root.calendarIsoDate(dayNumber, monthPage.monthOffset)
                                property double focusedSeconds: root.calendarCellSeconds(dayNumber, monthPage.monthOffset)
                                property bool today: root.isToday(dayNumber, monthPage.monthOffset)
                                property int weekRow: Math.floor(index / 7)

                                opacity: root.calendarWaveVisible ? 1 : 0
                                Behavior on opacity {
                                    SequentialAnimation {
                                        PauseAnimation {
                                            duration: (calendarDayCell.weekRow + 2) * 65
                                        }
                                        NumberAnimation {
                                            duration: 240
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                transform: Translate {
                                    y: root.calendarWaveVisible ? 0 : 7
                                    Behavior on y {
                                        SequentialAnimation {
                                            PauseAnimation {
                                                duration: (calendarDayCell.weekRow + 2) * 65
                                            }
                                            NumberAnimation {
                                                duration: 320
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: 6
                                    visible: calendarDayCell.dayNumber !== ""
                                    color: root.calendarCellBackground(
                                               calendarDayCell.focusedSeconds,
                                               calendarDayCell.today)
                                    border.color: calendarDayCell.today ? theme.accent : "transparent"
                                    border.width: calendarDayCell.today ? 1 : 0
                                    z: 0
                                }

                                Text {
                                    id: dayNumberText
                                    anchors.top: parent.top
                                    anchors.topMargin: 2
                                    width: parent.width
                                    height: 14
                                    text: calendarDayCell.dayNumber
                                    visible: calendarDayCell.dayNumber !== ""
                                    color: calendarDayCell.today ? theme.accent : theme.text
                                    font.pixelSize: 11
                                    font.weight: calendarDayCell.today ? Font.DemiBold : Font.Normal
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    z: 2
                                }

                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 5
                                    width: parent.width
                                    height: 12
                                    text: root.formatCalendarDuration(calendarDayCell.focusedSeconds)
                                    // Keep empty days clean; show HH:MM only after time is recorded.
                                    visible: calendarDayCell.dayNumber !== ""
                                             && calendarDayCell.focusedSeconds > 0
                                    color: theme.accent
                                    font.pixelSize: 9
                                    font.weight: calendarDayCell.focusedSeconds > 0 ? Font.Medium : Font.Normal
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    z: 2
                                }
                            }
                        }
                    }
                }
            }
        }

        NumberAnimation {
            id: calendarSnapAnimation
            target: root
            property: "calendarDragOffset"
            to: root.calendarCommitOffset === 0
                ? 0 : -root.calendarCommitOffset * calendarViewport.width
            duration: 140
            easing.type: Easing.OutCubic
            onFinished: {
                if (root.calendarCommitOffset !== 0) {
                    root.applyCalendarMonthOffset(root.calendarCommitOffset)
                    root.refreshCalendarData()
                }
                root.calendarDragOffset = 0
                root.calendarCommitOffset = 0
            }
        }

        // The gesture surface is limited to the calendar box.
        MouseArea {
            id: calendarSwipeArea
            anchors.fill: parent
            z: 10
            preventStealing: true

            onPressed: function(mouse) {
                if (calendarSnapAnimation.running) {
                    calendarSnapAnimation.stop()
                    root.calendarDragOffset = 0
                }

                root.calendarSwipeStartX = mouse.x
                root.calendarSwipeStartY = mouse.y
                root.calendarGestureDecided = false
                root.calendarHorizontalGesture = false
                root.calendarCommitOffset = 0
            }

            onPositionChanged: function(mouse) {
                if (!pressed)
                    return

                var dx = mouse.x - root.calendarSwipeStartX
                var dy = mouse.y - root.calendarSwipeStartY

                if (!root.calendarGestureDecided
                        && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
                    root.calendarGestureDecided = true
                    root.calendarHorizontalGesture = Math.abs(dx) > Math.abs(dy) * 1.15
                }

                if (root.calendarHorizontalGesture) {
                    calendarSnapAnimation.stop()
                    root.calendarDragOffset = Math.max(
                                -calendarViewport.width,
                                Math.min(calendarViewport.width, dx))
                }
            }

            onReleased: {
                root.calendarCommitOffset = 0
                if (root.calendarHorizontalGesture) {
                    var threshold = calendarViewport.width * 0.5
                    if (root.calendarDragOffset < -threshold)
                        root.calendarCommitOffset = 1
                    else if (root.calendarDragOffset > threshold)
                        root.calendarCommitOffset = -1
                }
                calendarSnapAnimation.start()
                root.calendarGestureDecided = false
                root.calendarHorizontalGesture = false
            }

            onCanceled: {
                root.calendarCommitOffset = 0
                calendarSnapAnimation.start()
                root.calendarGestureDecided = false
                root.calendarHorizontalGesture = false
            }
        }
    }

    // Mirrored counterpart of the daily-focus handle, attached to the calendar's right edge.
    Rectangle {
        id: calendarCardHandle
        x: (root.calendarExpanded ? 22 : 24 - monthlyCalendarCard.width) + monthlyCalendarCard.width - 12
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -8
            + (root.calendarHandleSettled
               ? Math.sin(root.calendarHandleCloudPhase * 2 * Math.PI) * 3 : 0)
        width: 38
        height: 54
        radius: 9
        color: calendarHandleHover.containsMouse
               ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14)
               : Qt.lighter(theme.surface, 1.0 + 0.11 * root.calendarHandleCloudPhase)
        border.color: calendarHandleHover.containsMouse
                      ? theme.accent
                      : Qt.lighter(theme.border, 1.0 + 0.06 * root.calendarHandleCloudPhase)
        border.width: calendarHandleHover.containsMouse ? 1.4 : 1
        z: 5
        opacity: root.introProgress(0.10)
        scale: calendarHandleHover.containsMouse
               ? 1.09 : (root.calendarHandleExpanded ? 1.02 : 0.96)

        transform: [
            Scale {
                origin.x: calendarCardHandle.width / 2
                origin.y: calendarCardHandle.height / 2
                xScale: 0.95 + 0.05 * root.introProgress(0.10)
                yScale: 0.95 + 0.05 * root.introProgress(0.10)
            },
            Translate {
                y: (1 - root.introProgress(0.10)) * 12
            }
        ]

        Behavior on x {
            SequentialAnimation {
                PauseAnimation { duration: 16 }
                NumberAnimation {
                    duration: 900
                    easing.type: Easing.OutExpo
                }
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutBack
            }
        }
        Behavior on color { ColorAnimation { duration: 220 } }
        Behavior on border.color { ColorAnimation { duration: 220 } }
        Behavior on border.width { NumberAnimation { duration: 180 } }

        Grid {
            anchors.centerIn: parent
            columns: 2
            rows: 3
            columnSpacing: 4
            rowSpacing: 4

            Repeater {
                model: 6
                delegate: Rectangle {
                    required property int index
                    width: 3
                    height: 3
                    radius: 1.5
                    color: calendarHandleHover.containsMouse ? theme.accent : theme.mutedText
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
            }
        }

        MouseArea {
            id: calendarHandleHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.calendarExpanded = !root.calendarExpanded
        }
    }

    // Timer sits lower with larger digits and a lighter set of controls.
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 72
        spacing: 15
        z: 3
        opacity: root.introProgress(0.20)
        scale: 0.96 + 0.04 * root.introProgress(0.20)

        transform: Translate {
            y: (1 - root.introProgress(0.20)) * 14
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: controller.formattedTime()
            color: theme.text
            font.pixelSize: 100
            font.weight: Font.Light
            font.kerning: false
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Button {
                id: stopwatchToggleButton
                text: controller.timerRunning ? "Pause" : "Start"
                implicitWidth: 108
                implicitHeight: 39
                font.pixelSize: 12
                font.weight: Font.DemiBold
                scale: hovered ? 1.035 : 1
                onClicked: root.toggleSelectedSubjectTimer()

                Behavior on scale {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                background: Rectangle {
                    radius: 11
                    color: stopwatchToggleButton.hovered
                           ? (controller.timerRunning
                              ? "#D8E8D8"
                              : (controller.elapsedMilliseconds > 0
                                 ? "#E8D0CE" : Qt.lighter(theme.accent, 1.08)))
                           : theme.accent
                    border.width: stopwatchToggleButton.hovered ? 1 : 0
                    border.color: controller.timerRunning ? "#6FA879"
                                 : (controller.elapsedMilliseconds > 0 ? "#C96B66" : theme.accent)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 10
                        color: "transparent"
                        border.width: stopwatchToggleButton.hovered ? 1 : 0
                        border.color: controller.timerRunning
                                      ? Qt.rgba(0.18, 0.55, 0.28, 0.42)
                                      : Qt.rgba(0.70, 0.22, 0.19, 0.34)
                        opacity: stopwatchToggleButton.hovered
                                 && (controller.timerRunning || controller.elapsedMilliseconds > 0)
                                 ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                }

                contentItem: Text {
                    text: stopwatchToggleButton.text
                    color: stopwatchToggleButton.hovered
                           && (controller.timerRunning || controller.elapsedMilliseconds > 0)
                           ? "#252525" : theme.accentText
                    font: stopwatchToggleButton.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    Behavior on color {
                        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                }
            }

            Button {
                id: stopwatchResetButton
                text: "↻"
                ToolTip.visible: hovered
                ToolTip.text: "Reset stopwatch"
                implicitWidth: 40
                implicitHeight: 39
                font.pixelSize: 17
                scale: hovered ? 1.08 : 1
                onClicked: controller.resetTimer()

                Behavior on scale {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutBack
                    }
                }

                background: Rectangle {
                    radius: 11
                    color: stopwatchResetButton.hovered ? Qt.lighter(theme.surface, 1.14) : theme.surface
                    border.width: stopwatchResetButton.hovered ? 1.2 : 1
                    border.color: stopwatchResetButton.hovered ? theme.accent : theme.border

                    Rectangle {
                        anchors.centerIn: parent
                        width: stopwatchResetButton.hovered ? 28 : 0
                        height: stopwatchResetButton.hovered ? 28 : 0
                        radius: 14
                        color: "transparent"
                        border.color: theme.accent
                        border.width: 1
                        opacity: stopwatchResetButton.hovered ? 0.55 : 0

                        Behavior on width {
                            NumberAnimation { duration: 240; easing.type: Easing.OutBack }
                        }
                        Behavior on height {
                            NumberAnimation { duration: 240; easing.type: Easing.OutBack }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }
                    }

                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                contentItem: Text {
                    text: stopwatchResetButton.text
                    color: stopwatchResetButton.hovered ? theme.accent : theme.text
                    font: stopwatchResetButton.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: controller.statusMessage.length > 0
            text: controller.statusMessage
            color: theme.mutedText
            font.pixelSize: 12
        }
    }

    // Only a slim strip of this independent card is visible initially.
    Rectangle {
        id: dailyFocusedCard
        x: root.width - (root.dailyCardExpanded ? width + 48 : 24)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -8
            + (root.dailyCardSettled
               ? Math.sin(root.dailyCardCloudPhase * 2 * Math.PI) * 3 : 0)
        width: 248
        height: 178
        radius: 16
        scale: root.dailyCardExpanded ? 1.02 : 0.96
        opacity: root.introProgress(0.32)
        transform: [
            Scale {
                origin.x: dailyFocusedCard.width / 2
                origin.y: dailyFocusedCard.height / 2
                xScale: 0.96 + 0.04 * root.introProgress(0.32)
                yScale: 0.96 + 0.04 * root.introProgress(0.32)
            },
            Translate {
                y: (1 - root.introProgress(0.32)) * 14
            }
        ]
        color: Qt.lighter(theme.surface, 1.0 + 0.11 * root.dailyCardCloudPhase)
        border.color: Qt.lighter(theme.border, 1.0 + 0.06 * root.dailyCardCloudPhase)
        border.width: 1
        z: 4

        Behavior on x {
            NumberAnimation {
                duration: 900
                easing.type: Easing.OutExpo
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 900
                easing.type: Easing.OutExpo
            }
        }

        Column {
            id: dailyCardContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 10

            transform: Translate {
                y: root.dailyCardSettled ? 0 : 8
                Behavior on y {
                    NumberAnimation {
                        duration: 500
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Text {
                id: focusedTimeText
                width: parent.width
                height: 58
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.formattedFocusedTime()
                color: theme.text
                font.pixelSize: 40
                font.weight: Font.Light
                minimumPixelSize: 28
                fontSizeMode: Text.Fit
                opacity: 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 190
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Rectangle {
                x: 12
                width: parent.width - 24
                height: 1
                color: Qt.lighter(theme.border, 1.0 + 0.06 * root.dailyCardCloudPhase)
                opacity: focusedTimeText.opacity
                Behavior on opacity {
                    NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
                }
            }

            Text {
                id: focusedDateText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.formattedDate()
                color: theme.mutedText
                font.pixelSize: 13
                opacity: 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    // Separate handle: x and expansion state trail the card by only 8 ms.
    Rectangle {
        id: dailyCardHandle
        x: root.width - (root.dailyCardExpanded ? dailyFocusedCard.width + 48 : 24) - 30
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -8
            + (root.dailyHandleSettled
               ? Math.sin(root.dailyHandleCloudPhase * 2 * Math.PI) * 3 : 0)
        width: 38
        height: 54
        radius: 9
        color: handleHover.containsMouse
               ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14)
               : Qt.lighter(theme.surface, 1.0 + 0.11 * root.dailyHandleCloudPhase)
        border.color: handleHover.containsMouse
                      ? theme.accent
                      : Qt.lighter(theme.border, 1.0 + 0.06 * root.dailyHandleCloudPhase)
        border.width: handleHover.containsMouse ? 1.4 : 1
        z: 5
        opacity: root.introProgress(0.40)
        scale: handleHover.containsMouse
               ? 1.09 : (root.handleExpanded ? 1.02 : 0.96)
        transform: [
            Scale {
                origin.x: dailyCardHandle.width / 2
                origin.y: dailyCardHandle.height / 2
                xScale: 0.95 + 0.05 * root.introProgress(0.40)
                yScale: 0.95 + 0.05 * root.introProgress(0.40)
            },
            Translate {
                y: (1 - root.introProgress(0.40)) * 12
            }
        ]

        Behavior on x {
            SequentialAnimation {
                PauseAnimation { duration: 16 }
                NumberAnimation {
                    duration: 900
                    easing.type: Easing.OutExpo
                }
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutBack
            }
        }
        Behavior on color { ColorAnimation { duration: 220 } }
        Behavior on border.color { ColorAnimation { duration: 220 } }
        Behavior on border.width { NumberAnimation { duration: 180 } }

        Grid {
            anchors.centerIn: parent
            columns: 2
            rows: 3
            columnSpacing: 4
            rowSpacing: 4

            Repeater {
                model: 6
                delegate: Rectangle {
                    required property int index
                    width: 3
                    height: 3
                    radius: 1.5
                    color: handleHover.containsMouse ? theme.accent : theme.mutedText
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
            }
        }

        MouseArea {
            id: handleHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dailyCardExpanded = !root.dailyCardExpanded
        }
    }
    } // pageContent

    // Modal overlay intentionally has no title-bar close button; Cancel is the dismissal action.
    Rectangle {
        id: subjectModalOverlay
        anchors.fill: parent
        visible: root.subjectDialogOpen
        color: "#B8000000"
        z: 100

        MouseArea {
            anchors.fill: parent
            onClicked: { /* Keep the form open until Add or Cancel is chosen. */ }
        }

        Rectangle {
            id: subjectModal
            anchors.centerIn: parent
            width: Math.min(440, parent.width - 36)
            height: 426
            radius: 18
            color: theme.surfaceRaised
            border.color: theme.border
            border.width: 1
            z: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 26
                spacing: 10

                Text {
                    text: "Add a subject"
                    color: theme.text
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    Layout.bottomMargin: 5
                }

                Text {
                    text: "Name"
                    color: theme.mutedText
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                TextField {
                    id: subjectNameInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    placeholderText: "e.g. Geopolitics"
                    text: root.newSubjectName
                    onTextChanged: root.newSubjectName = text
                    color: theme.text
                    selectionColor: theme.accent
                    selectedTextColor: theme.accentText
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: 13
                    background: Rectangle {
                        radius: 9
                        color: theme.window
                        border.width: subjectNameInput.activeFocus ? 1.4 : 1
                        border.color: subjectNameInput.activeFocus ? theme.accent : theme.border
                    }
                }

                Text {
                    text: "Colour"
                    color: theme.mutedText
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    spacing: 11

                    Repeater {
                        model: root.subjectColourPalette
                        delegate: Rectangle {
                            required property string modelData
                            Layout.preferredWidth: 27
                            Layout.preferredHeight: 27
                            radius: 13.5
                            color: modelData
                            border.width: root.newSubjectColour === modelData ? 3 : 1
                            border.color: root.newSubjectColour === modelData
                                          ? theme.text : Qt.rgba(1, 1, 1, 0.28)

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.newSubjectColour = modelData
                            }
                        }
                    }
                }

                Text {
                    text: "Goal (hours)"
                    color: theme.mutedText
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                TextField {
                    id: subjectGoalInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    placeholderText: "e.g. 5"
                    text: root.newSubjectGoal
                    onTextChanged: root.newSubjectGoal = text
                    color: theme.text
                    selectionColor: theme.accent
                    selectedTextColor: theme.accentText
                    leftPadding: 12
                    rightPadding: 12
                    font.pixelSize: 13
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: DoubleValidator {
                        bottom: 0.1
                        top: 10000
                        decimals: 2
                        notation: DoubleValidator.StandardNotation
                    }
                    background: Rectangle {
                        radius: 9
                        color: theme.window
                        border.width: subjectGoalInput.activeFocus ? 1.4 : 1
                        border.color: subjectGoalInput.activeFocus ? theme.accent : theme.border
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 18 : 0
                    visible: root.subjectFormError.length > 0
                    text: root.subjectFormError
                    color: "#F19A9A"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    spacing: 10

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "Cancel"
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 42
                        onClicked: root.closeSubjectDialog()
                        background: Rectangle {
                            radius: 9
                            color: parent.hovered ? theme.border : theme.surface
                            border.color: theme.border
                        }
                        contentItem: Text {
                            text: parent.text
                            color: theme.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Add"
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 42
                        enabled: root.newSubjectName.trim().length > 0
                                 && root.newSubjectGoal.trim().length > 0
                                 && Number(root.newSubjectGoal) > 0
                        onClicked: root.addSubject()
                        background: Rectangle {
                            radius: 9
                            color: parent.enabled ? theme.accent : theme.border
                        }
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? theme.accentText : theme.mutedText
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
