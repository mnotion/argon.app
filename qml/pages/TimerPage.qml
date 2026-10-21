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
    property real dailyCardCloudPhase: 0
    property bool calendarExpanded: false
    property bool calendarSettled: false
    property bool calendarWaveVisible: false
    property real calendarCloudPhase: 0
    property int displayedCalendarYear: new Date().getFullYear()
    property int displayedCalendarMonth: new Date().getMonth()
    property var calendarFocusedSeconds: ({})
    property string calendarTodayIsoDate: ""
    property double todayFocusedSeconds: 0
    property bool calendarDetailsVisible: false
    property string selectedCalendarDate: ""
    property var selectedCalendarSubjectFocus: []
    property real calendarDetailsWidth: Math.max(240, Math.min(380, root.width * 0.26, root.width - 700))
    property real calendarSwipeStartX: 0
    property real calendarSwipeStartY: 0
    property real calendarDragOffset: 0
    property int calendarCommitOffset: 0
    property bool calendarGestureDecided: false
    property bool calendarHorizontalGesture: false
    // Three vertically paged sections: timer + subjects, monthly analytics, daily focus.
    property int scrollSectionIndex: 0
    property int scrollSectionCount: 3
    property var subjects: []
    property var subjectDisplayOrder: []
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
        refreshSubjectDisplayOrder()
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
        refreshSubjectDisplayOrder()
        subjectDialogOpen = false
        subjectFormError = ""
    }

    function selectSubject(subjectId) {
        selectedSubjectId = String(subjectId)
        if (!appSettingsService.setValue("timer.selectedSubjectId", selectedSubjectId))
            console.warn("[Timer] Could not save the selected subject.")
    }

    function currentMonthKey() {
        var now = new Date()
        var month = now.getMonth() + 1
        return now.getFullYear() + "-" + (month < 10 ? "0" : "") + month
    }

    function monthlySubjectElapsed(subjectId) {
        var monthSubjectKey = currentMonthKey() + "|" + String(subjectId)
        return Math.max(0, Number(controller.subjectMonthlyElapsedMilliseconds[monthSubjectKey]) || 0)
    }

    function refreshSubjectDisplayOrder() {
        // Selection only changes highlighting. Recalculate periodically from this
        // month's totals, but replace the Repeater model only when the order changes.
        var ordered = subjects.slice()
        ordered.sort(function(a, b) {
            return root.monthlySubjectElapsed(b.id) - root.monthlySubjectElapsed(a.id)
        })

        var orderChanged = ordered.length !== subjectDisplayOrder.length
        if (!orderChanged) {
            for (var i = 0; i < ordered.length; ++i) {
                if (String(ordered[i].id) !== String(subjectDisplayOrder[i].id)) {
                    orderChanged = true
                    break
                }
            }
        }

        if (orderChanged)
            subjectDisplayOrder = ordered
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

    function moveScrollSection(direction) {
        if (root.subjectDialogOpen || sectionScrollCooldown.running)
            return

        var nextIndex = Math.max(0, Math.min(root.scrollSectionCount - 1,
                                              root.scrollSectionIndex + direction))
        if (nextIndex === root.scrollSectionIndex)
            return

        root.scrollSectionIndex = nextIndex
        sectionScrollCooldown.start()
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
        calendarDetailsVisible = false
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

    function calendarWeekCount(offset) {
        return Math.ceil((calendarFirstWeekday(offset) + calendarDaysInMonth(offset)) / 7)
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

    function selectCalendarDate(isoDate) {
        if (!isoDate)
            return
        selectedCalendarDate = String(isoDate)
        selectedCalendarSubjectFocus = dailyAnalyticsService.subjectFocusForDate(selectedCalendarDate)
        calendarDetailsVisible = true
    }

    function closeCalendarDetails() {
        calendarDetailsVisible = false
    }

    function refreshSelectedCalendarDetails() {
        if (selectedCalendarDate.length > 0)
            selectedCalendarSubjectFocus = dailyAnalyticsService.subjectFocusForDate(selectedCalendarDate)
    }

    function selectedCalendarTotalSeconds() {
        if (selectedCalendarDate.length === 0)
            return 0
        if (selectedCalendarDate === calendarTodayIsoDate)
            return todayFocusedSeconds
        return dailyAnalyticsService.focusedSecondsForDate(selectedCalendarDate)
    }

    function formattedSelectedCalendarDate() {
        if (selectedCalendarDate.length === 0)
            return ""
        return Qt.formatDate(new Date(selectedCalendarDate + "T12:00:00"), "dddd, d MMMM yyyy")
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
        dateFadeTimer.stop()

        if (dailyCardExpanded) {
            focusedTimeText.opacity = 0
            focusedDateText.opacity = 0
            cardSettleTimer.start()
        } else {
            dailyCardSettled = false
            dailyCardCloudPhase = 0
            focusedTimeText.opacity = 0
            focusedDateText.opacity = 0
        }
    }

    onCalendarExpandedChanged: {
        calendarSettleTimer.stop()
        calendarWaveRevealTimer.stop()

        if (calendarExpanded) {
            calendarWaveVisible = false
            calendarSettleTimer.start()
        } else {
            calendarSettled = false
            calendarCloudPhase = 0
            calendarWaveVisible = false
        }
    }

    onScrollSectionIndexChanged: {
        calendarExpanded = scrollSectionIndex === 1
        dailyCardExpanded = scrollSectionIndex === 2
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

    Timer {
        id: subjectOrderRefreshTimer
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.refreshSubjectDisplayOrder()
    }

    Connections {
        target: dailyAnalyticsService
        function onDailyStatsChanged() {
            root.refreshTodayCalendarData()
            if (root.selectedCalendarDate === root.calendarTodayIsoDate)
                root.refreshSelectedCalendarDetails()
        }
    }

    Timer {
        id: sectionScrollCooldown
        interval: 650
        repeat: false
    }

    // Wheel, touchpad, and stylus scrolling all move the page in the natural
    // content direction: scrolling down moves the visible section upward.
    WheelHandler {
        id: sectionWheelHandler
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        property real accumulatedDelta: 0

        onWheel: function(event) {
            event.accepted = true
            if (root.subjectDialogOpen || sectionScrollCooldown.running)
                return

            var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y
            accumulatedDelta += delta
            if (Math.abs(accumulatedDelta) < 18)
                return

            // Positive wheel delta means scrolling up; invert the section index
            // so positive/downward content motion reveals the next section.
            var direction = accumulatedDelta < 0 ? 1 : -1
            accumulatedDelta = 0
            root.moveScrollSection(direction)
        }
    }

    // A real vertical pointer gesture for fingers and stylus pens.
    // WheelHandler alone cannot handle an ordinary touchscreen swipe.
    DragHandler {
        id: sectionTouchDragHandler
        target: null
        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
        acceptedPointerTypes: PointerDevice.Finger | PointerDevice.Pen
        acceptedButtons: Qt.NoButton
        dragThreshold: 24
        xAxis.enabled: false
        yAxis.enabled: true

        property real capturedX: 0
        property real capturedY: 0

        onActiveChanged: {
            if (active) {
                capturedX = 0
                capturedY = 0
                return
            }

            var swipeX = capturedX
            var swipeY = capturedY
            capturedX = 0
            capturedY = 0

            if (root.subjectDialogOpen || Math.abs(swipeY) < 58
                    || Math.abs(swipeY) <= Math.abs(swipeX) * 1.2)
                return

            // Moving the finger/stylus up advances the content down the stack.
            root.moveScrollSection(swipeY < 0 ? 1 : -1)
        }

        onActiveTranslationChanged: {
            if (active) {
                capturedX = activeTranslation.x
                capturedY = activeTranslation.y
            }
        }

        onCanceled: {
            capturedX = 0
            capturedY = 0
        }
    }

    Item {
        id: pageContent
        anchors.fill: parent
        clip: true
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
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: (stopwatchControlStack.height + 54 - addSubjectButton.height - 8) / 2
        width: Math.min(560, parent.width - 80)
        height: Math.min(260, Math.max(196, parent.height * 0.36))
        radius: 18
        color: theme.surface
        border.color: theme.border
        border.width: 1
        z: 2
        transform: Translate {
            y: -root.scrollSectionIndex * root.height
            Behavior on y {
                NumberAnimation { duration: 620; easing.type: Easing.InOutCubic }
            }
        }

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
                    model: root.subjectDisplayOrder
                    delegate: Rectangle {
                        required property var modelData
                        readonly property var subjectData: modelData
                        readonly property color subjectAccent: String(subjectData.colour)
                        readonly property bool isSelected: root.selectedSubjectId === String(subjectData.id)
                        width: subjectRowsColumn.width
                        height: 44
                        radius: 10
                        // A very subtle tint from the subject colour fills the whole card.
                        color: isSelected
                               ? Qt.rgba(subjectAccent.r, subjectAccent.g, subjectAccent.b, 0.075)
                               : Qt.rgba(subjectAccent.r, subjectAccent.g, subjectAccent.b, 0.035)
                        border.width: isSelected ? 1.5 : 1
                        border.color: isSelected
                                      ? Qt.rgba(subjectAccent.r, subjectAccent.g, subjectAccent.b, 0.62)
                                      : theme.border
                        clip: true

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
        transform: Translate {
            y: -root.scrollSectionIndex * root.height
            Behavior on y {
                NumberAnimation { duration: 620; easing.type: Easing.InOutCubic }
            }
        }

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
        x: root.calendarDetailsVisible
           ? (root.width - (width + 24 + root.calendarDetailsWidth)) / 2
           : (root.width - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -8
            + (root.calendarSettled
               ? Math.sin(root.calendarCloudPhase * 2 * Math.PI) * 3 : 0)
        width: root.calendarDetailsVisible
               ? Math.min(660, Math.max(340, parent.width - root.calendarDetailsWidth - 124))
               : Math.min(760, Math.max(380, parent.width * 0.58))
        height: Math.min(parent.height - 64, 660,
                         Math.max(420, 190 + root.calendarWeekCount(0) * 78))
        radius: 20
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
            },
            Translate {
                y: (1 - root.scrollSectionIndex) * root.height
                Behavior on y {
                    NumberAnimation { duration: 620; easing.type: Easing.InOutCubic }
                }
            }
        ]

        Behavior on x {
            NumberAnimation {
                duration: 460
                easing.type: Easing.OutCubic
            }
        }
        Behavior on width {
            NumberAnimation {
                duration: 460
                easing.type: Easing.OutCubic
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
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 30
            anchors.bottomMargin: 22
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
                    spacing: 16

                    Row {
                        id: calendarMonthHeading
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 5
                        height: 38
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
                            height: 38

                            Text {
                                id: monthNameText
                                anchors.centerIn: parent
                                text: root.calendarMonthName(monthPage.monthOffset)
                                color: root.isCurrentMonthOffset(monthPage.monthOffset)
                                       ? theme.accent : theme.text
                                font.pixelSize: 29
                                font.weight: root.isCurrentMonthOffset(monthPage.monthOffset)
                                             ? Font.DemiBold : Font.Medium
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.calendarYearText(monthPage.monthOffset)
                            color: theme.mutedText
                            font.pixelSize: 24
                            font.weight: Font.Normal
                        }
                    }

                    Text {
                        id: calendarMonthTotalLabel
                        width: parent.width
                        height: 20
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
                        text: "Monthly Focus: " + root.formatCalendarDuration(
                                  root.calendarMonthTotalSeconds(monthPage.monthOffset))
                        color: theme.mutedText
                        font.pixelSize: 13
                        font.capitalization: Font.MixedCase
                        font.letterSpacing: 0.2
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
                                height: 32
                                text: modelData
                                color: theme.mutedText
                                font.pixelSize: 15
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
                            model: root.calendarWeekCount(monthPage.monthOffset) * 7
                            delegate: Item {
                                id: calendarDayCell
                                required property int index
                                width: calendarViewport.width / 7
                                height: Math.max(42,
                                    (calendarViewport.height - 138
                                     - 3 * (root.calendarWeekCount(monthPage.monthOffset) - 1))
                                    / root.calendarWeekCount(monthPage.monthOffset))

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
                                    color: root.calendarDetailsVisible
                                           && root.selectedCalendarDate === calendarDayCell.isoDate
                                           ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.24)
                                           : root.calendarCellBackground(
                                                 calendarDayCell.focusedSeconds,
                                                 calendarDayCell.today)
                                    border.color: root.calendarDetailsVisible
                                                  && root.selectedCalendarDate === calendarDayCell.isoDate
                                                  ? theme.accent
                                                  : (calendarDayCell.today ? theme.accent : "transparent")
                                    border.width: root.calendarDetailsVisible
                                                  && root.selectedCalendarDate === calendarDayCell.isoDate
                                                  ? 1.7 : (calendarDayCell.today ? 1 : 0)
                                    z: 0
                                }

                                Text {
                                    id: dayNumberText
                                    anchors.top: parent.top
                                    anchors.topMargin: 5
                                    width: parent.width
                                    height: 22
                                    text: calendarDayCell.dayNumber
                                    visible: calendarDayCell.dayNumber !== ""
                                    color: calendarDayCell.today ? theme.accent : theme.text
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    z: 2
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: parent.height * 0.15
                                    width: parent.width
                                    height: 16
                                    text: root.formatCalendarDuration(calendarDayCell.focusedSeconds)
                                    // Keep empty days clean; show HH:MM only after time is recorded.
                                    visible: calendarDayCell.dayNumber !== ""
                                             && calendarDayCell.focusedSeconds > 0
                                    color: theme.accent
                                    font.pixelSize: 12
                                    font.weight: Font.Normal
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    z: 2
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    z: 4
                                    enabled: calendarDayCell.dayNumber !== ""
                                    acceptedButtons: Qt.LeftButton
                                    hoverEnabled: true
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.selectCalendarDate(calendarDayCell.isoDate)
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

        // DragHandler leaves ordinary taps available to each date cell.
        DragHandler {
            id: calendarHorizontalDragHandler
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                             | PointerDevice.TouchScreen | PointerDevice.Stylus
            dragThreshold: 8
            xAxis.enabled: true
            yAxis.enabled: false

            property real capturedX: 0

            onActiveChanged: {
                if (active) {
                    calendarSnapAnimation.stop()
                    capturedX = 0
                    root.calendarDragOffset = 0
                    root.calendarCommitOffset = 0
                    return
                }

                var swipeX = capturedX
                capturedX = 0
                if (Math.abs(swipeX) < 20) {
                    root.calendarDragOffset = 0
                    return
                }

                var threshold = calendarViewport.width * 0.35
                if (root.calendarDragOffset < -threshold)
                    root.calendarCommitOffset = 1
                else if (root.calendarDragOffset > threshold)
                    root.calendarCommitOffset = -1
                else
                    root.calendarCommitOffset = 0

                calendarSnapAnimation.start()
            }

            onActiveTranslationChanged: {
                if (active) {
                    capturedX = activeTranslation.x
                    root.calendarDragOffset = Math.max(
                                -calendarViewport.width,
                                Math.min(calendarViewport.width, activeTranslation.x))
                }
            }

            onCanceled: {
                capturedX = 0
                root.calendarCommitOffset = 0
                calendarSnapAnimation.start()
            }
        }
    }

    // Selected-date details expand alongside the calendar.
    Rectangle {
        id: calendarDetailsPanel
        x: monthlyCalendarCard.x + monthlyCalendarCard.width + 24
        anchors.verticalCenter: parent.verticalCenter
        width: root.calendarDetailsWidth
        height: monthlyCalendarCard.height
        radius: 20
        color: theme.surface
        border.color: theme.border
        border.width: 1
        z: 5
        visible: root.calendarDetailsVisible || opacity > 0.01
        opacity: root.calendarDetailsVisible ? root.introProgress(0.02) : 0
        scale: root.calendarDetailsVisible ? 1 : 0.94

        transform: Translate {
            y: (1 - root.scrollSectionIndex) * root.height
            Behavior on y {
                NumberAnimation { duration: 620; easing.type: Easing.InOutCubic }
            }
        }

        Behavior on x {
            NumberAnimation { duration: 460; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.formattedSelectedCalendarDate()
                    color: theme.text
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }

                Button {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    text: "×"
                    font.pixelSize: 21
                    onClicked: root.closeCalendarDetails()
                    background: Rectangle {
                        radius: 8
                        color: parent.hovered ? theme.border : "transparent"
                    }
                    contentItem: Text {
                        text: parent.text
                        color: theme.mutedText
                        font: parent.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Text {
                text: "DAILY FOCUS"
                color: theme.mutedText
                font.pixelSize: 10
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
            }

            Text {
                text: root.formatCalendarDuration(root.selectedCalendarTotalSeconds())
                color: theme.accent
                font.pixelSize: 34
                font.weight: Font.Light
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: theme.border
            }

            Text {
                text: "Subjects studied"
                color: theme.text
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                visible: root.selectedCalendarSubjectFocus.length === 0
                text: root.selectedCalendarTotalSeconds() > 0
                      ? "Focus time was recorded, but no subject breakdown is available for this date."
                      : "No focus recorded on this date yet."
                color: theme.mutedText
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 9

                Repeater {
                    model: root.selectedCalendarSubjectFocus

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumHeight: 36
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 9
                            Layout.preferredHeight: 9
                            radius: 4.5
                            color: String(modelData.colour || "#8CBFFF")
                        }

                        Text {
                            Layout.fillWidth: true
                            text: String(modelData.name || "Subject")
                            color: theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            text: root.formatCalendarDuration(Number(modelData.seconds) || 0)
                            color: theme.accent
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // Keep the timer directly above the subjects panel and make the digits prominent.
    ColumnLayout {
        id: stopwatchControlStack
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: subjectsPanel.top
        anchors.bottomMargin: 54
        spacing: 8
        z: 3
        opacity: root.introProgress(0.20)
        scale: 0.96 + 0.04 * root.introProgress(0.20)

        transform: [
            Translate {
                y: (1 - root.introProgress(0.20)) * 14
            },
            Translate {
                y: -root.scrollSectionIndex * root.height
                Behavior on y {
                    NumberAnimation { duration: 620; easing.type: Easing.InOutCubic }
                }
            }
        ]

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: controller.formattedTime()
            color: theme.text
            font.pixelSize: 156
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
        x: (root.width - width) / 2
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
            },
            Translate {
                y: (2 - root.scrollSectionIndex) * root.height
                Behavior on y {
                    NumberAnimation { duration: 620; easing.type: Easing.InOutCubic }
                }
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

} // pageContent

    // Fixed page indicator. It stays anchored to the window while sections move.
    Item {
        id: verticalSectionIndicator
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: sectionDotsColumn.implicitHeight
        z: 90
        visible: !root.subjectDialogOpen
        opacity: 0.92

        Column {
            id: sectionDotsColumn
            anchors.centerIn: parent
            spacing: 13

            Repeater {
                model: root.scrollSectionCount
                delegate: Item {
                    required property int index
                    width: 22
                    height: 12

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.scrollSectionIndex === index ? 10 : 6
                        height: width
                        radius: width / 2
                        color: root.scrollSectionIndex === index ? theme.accent : theme.mutedText
                        opacity: root.scrollSectionIndex === index ? 1 : 0.48

                        Behavior on width {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }
    }

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
