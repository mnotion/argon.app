import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../themes"

Item {
    id: root
    property bool lightMode: false
    property string accentColor: "#8CBFFF"
    Theme {
        id: theme
        lightMode: root.lightMode
        accent: root.accentColor
    }
    signal pageSelected(string pageName)

    property var controller: null
    property bool calendarExpanded: false
    property bool calendarSettled: false
    property bool calendarWaveVisible: false
    property real calendarCloudPhase: 0
    property int displayedCalendarYear: new Date().getFullYear()
    property int displayedCalendarMonth: new Date().getMonth()
    property var calendarFocusedSeconds: ({})
    property string calendarTodayIsoDate: ""
    property double todayFocusedSeconds: 0
    property var weeklyFocusPoints: []
    property int weeklyYAxisMax: 3
    property string historyPeriod: "weekly"
    property int historyChartYear: new Date().getFullYear()
    property int historyChartMonth: new Date().getMonth()
    property real historyRevealProgress: 0
    property int hoveredWeeklyPointIndex: -1
    property real historyHoverX: 0
    property real historyHoverY: 0
    property bool calendarDetailsVisible: false
    property real calendarDetailsProgress: calendarDetailsVisible ? 1 : 0
    property string selectedCalendarDate: ""
    property var selectedCalendarSubjectFocus: []
    property real calendarDetailsWidth: Math.max(240, Math.min(380, root.width * 0.26, root.width - 700))
    property real calendarDragOffset: 0

    // A single easing progress drives both calendar geometry and the panel reveal,
    // so the two elements always animate together instead of competing Behaviors.
    Behavior on calendarDetailsProgress {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutCubic
        }
    }
    property int calendarCommitOffset: 0
    // Three vertically paged sections: timer + subjects, monthly calendar, weekly history chart.
    property int scrollSectionIndex: 0
    property int scrollSectionCount: 3
    property var subjects: []
    property var subjectDisplayOrder: []
    property string selectedSubjectId: ""
    property bool subjectDialogOpen: false
    property string editingSubjectId: ""
    property string newSubjectName: ""
    property string newSubjectGoal: ""
    property string newSubjectColour: "#8CBFFF"
    property string subjectFormError: ""
    property bool subjectContextMenuOpen: false
    property string contextMenuSubjectId: ""
    property real subjectContextMenuX: 0
    property real subjectContextMenuY: 0
    property int deleteConfirmStage: 0
    property bool secondDeleteConfirmationPending: false
    property string deleteSubjectId: ""
    property string subjectDeleteError: ""
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
        editingSubjectId = ""
        newSubjectName = ""
        newSubjectGoal = ""
        newSubjectColour = subjectColourPalette[0]
        subjectFormError = ""
        subjectDialogOpen = true
        Qt.callLater(function() { subjectNameInput.forceActiveFocus() })
    }

    function openEditSubjectDialog(subjectId) {
        var targetId = String(subjectId)
        var target = null
        for (var i = 0; i < subjects.length; ++i) {
            if (String(subjects[i].id) === targetId) {
                target = subjects[i]
                break
            }
        }
        if (target === null)
            return

        subjectContextMenuOpen = false
        contextMenuSubjectId = ""
        editingSubjectId = targetId
        newSubjectName = String(target.name || "")
        newSubjectGoal = String(Number(target.goalHours) || "")
        newSubjectColour = String(target.colour || subjectColourPalette[0])
        subjectFormError = ""
        subjectDialogOpen = true
        Qt.callLater(function() { subjectNameInput.forceActiveFocus() })
    }

    function closeSubjectDialog() {
        subjectDialogOpen = false
        editingSubjectId = ""
        subjectFormError = ""
    }

    function openSubjectContextMenu(subjectId, sourceItem, sourceX, sourceY) {
        if (root.subjectDialogOpen || root.deleteConfirmStage > 0)
            return
        contextMenuSubjectId = String(subjectId)
        var point = sourceItem.mapToItem(root, sourceX, sourceY)
        subjectContextMenuX = Math.max(8, Math.min(root.width - 176, point.x))
        subjectContextMenuY = Math.max(8, Math.min(root.height - 104, point.y))
        subjectContextMenuOpen = true
    }

    function requestSubjectDelete() {
        deleteSubjectId = contextMenuSubjectId
        contextMenuSubjectId = ""
        subjectContextMenuOpen = false
        subjectDeleteError = ""
        deleteConfirmStage = 1
    }

    function confirmSubjectDelete() {
        if (deleteConfirmStage === 1) {
            subjectDeleteError = ""
            // Fade out the first warning before reopening with the final wording.
            deleteConfirmStage = 0
            secondDeleteConfirmationPending = true
            deleteConfirmReopenTimer.restart()
            return
        }
        if (deleteConfirmStage === 2)
            deleteSubjectForever()
    }

    function cancelSubjectDelete() {
        deleteConfirmReopenTimer.stop()
        secondDeleteConfirmationPending = false
        deleteConfirmStage = 0
        deleteSubjectId = ""
        subjectDeleteError = ""
    }

    function deleteSubjectForever() {
        var targetId = deleteSubjectId
        var updatedSubjects = subjects.filter(function(subject) {
            return String(subject.id) !== targetId
        })
        if (updatedSubjects.length === subjects.length) {
            cancelSubjectDelete()
            return
        }

        var deletingActiveSubject = String(controller.activeSubjectId) === targetId
        // Attribute the final running interval while the subject metadata still exists.
        if (deletingActiveSubject && controller.timerRunning)
            controller.tick()

        if (!appSettingsService.setValue("timer.subjects", updatedSubjects)) {
            subjectDeleteError = "Could not save the deletion. Please try again."
            return
        }

        if (deletingActiveSubject) {
            controller.timerRunning = false
            controller.activeSubjectId = ""
            controller.statusMessage = "Paused."
            controller.persistElapsedState()
        }

        subjects = updatedSubjects
        if (String(selectedSubjectId) === targetId) {
            selectedSubjectId = ""
            if (!appSettingsService.setValue("timer.selectedSubjectId", "")) {
                console.warn("[Timer] Could not clear the deleted selected subject.")
            }
        }
        if (editingSubjectId === targetId)
            closeSubjectDialog()

        // Remove the deleted card's lifetime and monthly ordering counters as well.
        var remainingLifetimeTotals = {}
        var lifetimeKeys = Object.keys(controller.subjectElapsedMilliseconds || ({}))
        for (var lifetimeIndex = 0; lifetimeIndex < lifetimeKeys.length; ++lifetimeIndex) {
            var lifetimeKey = lifetimeKeys[lifetimeIndex]
            if (String(lifetimeKey) !== targetId)
                remainingLifetimeTotals[lifetimeKey] = controller.subjectElapsedMilliseconds[lifetimeKey]
        }
        controller.subjectElapsedMilliseconds = remainingLifetimeTotals

        var remainingMonthlyTotals = {}
        var monthlyKeys = Object.keys(controller.subjectMonthlyElapsedMilliseconds || ({}))
        for (var monthlyIndex = 0; monthlyIndex < monthlyKeys.length; ++monthlyIndex) {
            var monthlyKey = monthlyKeys[monthlyIndex]
            if (String(monthlyKey).slice(monthlyKey.lastIndexOf("|") + 1) !== targetId)
                remainingMonthlyTotals[monthlyKey] = controller.subjectMonthlyElapsedMilliseconds[monthlyKey]
        }
        controller.subjectMonthlyElapsedMilliseconds = remainingMonthlyTotals
        controller.persistElapsedState()

        refreshSubjectDisplayOrder()
        cancelSubjectDelete()
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

        if (editingSubjectId.length > 0) {
            var editedId = editingSubjectId
            var editedSubjects = subjects.map(function(subject) {
                if (String(subject.id) !== editedId)
                    return subject
                return {
                    "id": String(subject.id),
                    "name": name,
                    "colour": String(newSubjectColour),
                    "goalHours": goalHours
                }
            })
            var foundEditedSubject = editedSubjects.some(function(subject) {
                return String(subject.id) === editedId
            })
            if (!foundEditedSubject) {
                subjectFormError = "This subject no longer exists."
                return
            }
            if (!appSettingsService.setValue("timer.subjects", editedSubjects)) {
                subjectFormError = "The subject could not be saved. Please try again."
                return
            }
            subjects = editedSubjects
            refreshSubjectDisplayOrder()
            closeSubjectDialog()
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
        closeSubjectDialog()
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
        } else {
            todayFocusedSeconds = dailyAnalyticsService.focusedSecondsForDate(currentDateKey)
        }
        refreshHistoryChartData()
    }

    function setHistoryPeriod(period) {
        if (period !== "weekly" && period !== "monthly" && period !== "daily")
            return

        historyPeriod = period
        if (period === "monthly") {
            var today = new Date()
            historyChartYear = today.getFullYear()
            historyChartMonth = today.getMonth()
        }

        hoveredWeeklyPointIndex = -1
        historyRevealAnimation.stop()
        historyRevealProgress = 0
        refreshHistoryChartData()
        if (scrollSectionIndex === 2)
            historyRevealAnimation.start()
    }

    function historyChartTitle() {
        if (historyPeriod === "monthly") {
            return Qt.formatDate(
                        new Date(historyChartYear, historyChartMonth, 1),
                        "MMMM yyyy")
        }

        var today = new Date()
        if (historyPeriod === "daily")
            return Qt.formatDate(today, "dddd d MMMM yyyy")

        // Weeks are fixed blocks within each month: 1–7, 8–14, 15–21, 22–28, 29–31.
        var weekNumber = Math.floor((today.getDate() - 1) / 7) + 1
        return "Week " + weekNumber + " " + Qt.formatDate(today, "MMMM yyyy")
    }

    function refreshHistoryChartData() {
        var today = new Date()
        today.setHours(0, 0, 0, 0)
        var todayKey = calendarDateKey(today)
        var points = []
        var maxSeconds = 0

        if (historyPeriod === "daily") {
            var hourlySeconds = dailyAnalyticsService.focusedSecondsByHourForDate(todayKey)
            for (var hour = 0; hour < 24; ++hour) {
                var hourSeconds = Math.max(0, Number(hourlySeconds[hour]) || 0)
                points.push({
                    "date": todayKey,
                    "weekday": Qt.formatDate(today, "ddd"),
                    "day": today.getDate(),
                    "hour": hour,
                    "label": hour,
                    "seconds": hourSeconds
                })
                maxSeconds = Math.max(maxSeconds, hourSeconds)
            }
        } else {
            var rangeStart
            var dayCount

            if (historyPeriod === "monthly") {
                rangeStart = new Date(historyChartYear, historyChartMonth, 1)
                dayCount = new Date(historyChartYear, historyChartMonth + 1, 0).getDate()
            } else {
                // Use the month-relative seven-day blocks instead of Monday–Sunday.
                var weekOffset = Math.floor((today.getDate() - 1) / 7) * 7
                var daysInCurrentMonth = new Date(
                            today.getFullYear(), today.getMonth() + 1, 0).getDate()
                rangeStart = new Date(today.getFullYear(), today.getMonth(), weekOffset + 1)
                dayCount = Math.min(7, daysInCurrentMonth - weekOffset)
            }

            for (var dayIndex = 0; dayIndex < dayCount; ++dayIndex) {
                var date = new Date(rangeStart.getTime())
                date.setDate(rangeStart.getDate() + dayIndex)
                var key = calendarDateKey(date)
                var seconds = Math.max(
                            0, Number(dailyAnalyticsService.focusedSecondsForDate(key)) || 0)

                if (key === todayKey) {
                    seconds = Math.max(
                                seconds, Number(dailyAnalyticsService.focusedSecondsToday) || 0)
                }

                points.push({
                    "date": key,
                    "weekday": Qt.formatDate(date, "ddd"),
                    "day": date.getDate(),
                    "label": historyPeriod === "weekly" ? dayIndex + 1 : date.getDate(),
                    "seconds": seconds
                })
                maxSeconds = Math.max(maxSeconds, seconds)
            }
        }

        weeklyFocusPoints = points
        // Leave three full hours above the busiest plotted day/hour; empty charts start at 3h.
        weeklyYAxisMax = Math.max(3, Math.ceil(maxSeconds / 3600) + 3)
        if (hoveredWeeklyPointIndex >= points.length)
            hoveredWeeklyPointIndex = -1
    }

    function formatWeeklyDuration(seconds) {
        var totalMinutes = Math.floor(Math.max(0, Number(seconds) || 0) / 60)
        var hours = Math.floor(totalMinutes / 60)
        var minutes = totalMinutes % 60
        if (hours === 0)
            return minutes + " min"
        if (minutes === 0)
            return hours + (hours === 1 ? " hour" : " hours")
        return hours + "h " + minutes + " min"
    }

    onScrollSectionIndexChanged: {
        // The calendar reveal remains tied to the same section state as before.
        calendarExpanded = scrollSectionIndex === 1
        if (scrollSectionIndex === 2) {
            hoveredWeeklyPointIndex = -1
            historyRevealAnimation.stop()
            historyRevealProgress = 0
            historyRevealAnimation.start()
        } else {
            hoveredWeeklyPointIndex = -1
            historyRevealAnimation.stop()
            historyRevealProgress = 0
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

    NumberAnimation {
        id: timerPageEntrance
        target: root
        property: "timerIntroProgress"
        from: 0
        to: 1
        duration: 920
        easing.type: Easing.OutCubic
    }

    // Animate only the graph's internals; the card itself scrolls like every other page.
    NumberAnimation {
        id: historyRevealAnimation
        target: root
        property: "historyRevealProgress"
        from: 0
        to: 1
        duration: 1150
        easing.type: Easing.OutCubic
    }

    Component.onCompleted: {
        dailyAnalyticsService.refreshToday()
        refreshCalendarData()
        refreshHistoryChartData()
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
        layer.enabled: root.subjectDialogOpen || root.deleteConfirmStage > 0
        layer.effect: MultiEffect {
            blurEnabled: root.subjectDialogOpen || root.deleteConfirmStage > 0
            blur: (root.subjectDialogOpen || root.deleteConfirmStage > 0) ? 0.9 : 0
            blurMax: 32
        }

        Rectangle {
            anchors.fill: parent
            color: theme.window
        }

    // Center the timer, subject list, and Add action as one size-aware group.
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
                            id: subjectBodyMouse
                            anchors.fill: parent
                            anchors.rightMargin: 2
                            z: 1
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (mouse.button === Qt.RightButton) {
                                    root.openSubjectContextMenu(
                                                subjectData.id, subjectBodyMouse, mouse.x, mouse.y)
                                } else {
                                    root.subjectContextMenuOpen = false
                                    root.selectSubject(subjectData.id)
                                }
                            }
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
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (mouse.button === Qt.RightButton) {
                                        root.openSubjectContextMenu(
                                                    subjectData.id, subjectTimerMouse, mouse.x, mouse.y)
                                    } else {
                                        root.subjectContextMenuOpen = false
                                        root.startSubjectTimer(subjectData.id)
                                    }
                                }
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
        width: Math.min(760, Math.max(380, parent.width * 0.58))
               + (Math.min(660, Math.max(340, parent.width - root.calendarDetailsWidth - 124))
                  - Math.min(760, Math.max(380, parent.width * 0.58)))
                 * root.calendarDetailsProgress
        x: (root.width - (width
                          + root.calendarDetailsProgress * (24 + root.calendarDetailsWidth))) / 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -8
            + (root.calendarSettled
               ? Math.sin(root.calendarCloudPhase * 2 * Math.PI) * 3 : 0)
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

        // Keep x/width updates synchronous with the details panel to avoid
        // intermediate off-screen positions on normal-sized windows.
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
        visible: root.calendarDetailsProgress > 0.001
        opacity: root.calendarDetailsProgress
        scale: 0.94 + 0.06 * root.calendarDetailsProgress

        transform: Translate {
            y: (1 - root.scrollSectionIndex) * root.height
            Behavior on y {
                NumberAnimation { duration: 620; easing.type: Easing.InOutCubic }
            }
        }

        // Position and reveal follow calendarDetailsProgress in the same frame.
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

            Flickable {
                id: subjectBreakdownViewport
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: subjectBreakdownColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: subjectBreakdownColumn
                    width: subjectBreakdownViewport.width
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
            }
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

    // Weekly history: point-to-point daily focus totals for Monday through Sunday.
    Rectangle {
        id: weeklyHistoryCard
        x: (root.width - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -6
        width: Math.min(1060, parent.width - 96)
        height: Math.min(parent.height - 72, 620)
        radius: 20
        color: theme.surface
        border.color: theme.border
        border.width: 1
        z: 4
        opacity: root.introProgress(0.32)
        scale: 0.97 + 0.03 * root.introProgress(0.32)
        transform: [
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
        Behavior on scale {
            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 26
            anchors.rightMargin: 26
            anchors.topMargin: 20
            anchors.bottomMargin: 16
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                spacing: 12

                Text {
                    text: root.historyChartTitle()
                    color: theme.accent
                    font.pixelSize: 25
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 6

                    Button {
                        id: weeklyHistoryButton
                        text: "Weekly"
                        hoverEnabled: true
                        checked: root.historyPeriod === "weekly"
                        onClicked: root.setHistoryPeriod("weekly")
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: 82
                        background: Rectangle {
                            radius: 9
                            color: weeklyHistoryButton.checked
                                   ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.20)
                                   : (weeklyHistoryButton.hovered ? theme.surface : theme.surfaceRaised)
                            border.color: weeklyHistoryButton.checked || weeklyHistoryButton.hovered
                                          ? theme.accent : theme.border
                            border.width: weeklyHistoryButton.checked ? 1.4 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: Text {
                            text: weeklyHistoryButton.text
                            color: weeklyHistoryButton.checked ? theme.accent : theme.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        id: monthlyHistoryButton
                        text: "Monthly"
                        hoverEnabled: true
                        checked: root.historyPeriod === "monthly"
                        onClicked: root.setHistoryPeriod("monthly")
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: 86
                        background: Rectangle {
                            radius: 9
                            color: monthlyHistoryButton.checked
                                   ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.20)
                                   : (monthlyHistoryButton.hovered ? theme.surface : theme.surfaceRaised)
                            border.color: monthlyHistoryButton.checked || monthlyHistoryButton.hovered
                                          ? theme.accent : theme.border
                            border.width: monthlyHistoryButton.checked ? 1.4 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: Text {
                            text: monthlyHistoryButton.text
                            color: monthlyHistoryButton.checked ? theme.accent : theme.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        id: dailyHistoryButton
                        text: "Daily"
                        hoverEnabled: true
                        checked: root.historyPeriod === "daily"
                        onClicked: root.setHistoryPeriod("daily")
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: 72
                        background: Rectangle {
                            radius: 9
                            color: dailyHistoryButton.checked
                                   ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.20)
                                   : (dailyHistoryButton.hovered ? theme.surface : theme.surfaceRaised)
                            border.color: dailyHistoryButton.checked || dailyHistoryButton.hovered
                                          ? theme.accent : theme.border
                            border.width: dailyHistoryButton.checked ? 1.4 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: Text {
                            text: dailyHistoryButton.text
                            color: dailyHistoryButton.checked ? theme.accent : theme.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Daily focus time"
                color: theme.mutedText
                font.pixelSize: 12
            }

            Item {
                id: historyPlot
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 260

                Canvas {
                    id: historyCanvas
                    anchors.fill: parent
                    antialiasing: true

                    readonly property real plotLeft: 66
                    readonly property real plotTop: 14
                    readonly property real plotRight: width - 12
                    readonly property real plotBottom: height - 42
                    readonly property real plotWidth: Math.max(1, plotRight - plotLeft)
                    readonly property real plotHeight: Math.max(1, plotBottom - plotTop)

                    function pointX(index) {
                        if (root.historyPeriod === "daily")
                            return plotLeft + ((index + 0.5) / 24) * plotWidth
                        var pointCount = root.weeklyFocusPoints.length
                        return plotLeft + index * plotWidth / Math.max(1, pointCount - 1)
                    }

                    function pointY(index) {
                        var seconds = Number(root.weeklyFocusPoints[index]
                                             ? root.weeklyFocusPoints[index].seconds : 0) || 0
                        var hours = seconds / 3600
                        return plotBottom - Math.min(root.weeklyYAxisMax, hours)
                                / root.weeklyYAxisMax * plotHeight
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        var progress = Math.max(0, Math.min(1, root.historyRevealProgress))
                        if (progress <= 0)
                            return

                        var left = plotLeft
                        var right = plotRight
                        var top = plotTop
                        var bottom = plotBottom
                        var graphWidth = plotWidth
                        var graphHeight = plotHeight
                        var visibleRight = left + graphWidth * progress
                        var visibleTop = bottom - graphHeight * progress
                        var pointCount = root.weeklyFocusPoints.length
                        var accentR = Math.round(theme.accent.r * 255)
                        var accentG = Math.round(theme.accent.g * 255)
                        var accentB = Math.round(theme.accent.b * 255)
                        var accentCss = "rgb(" + accentR + "," + accentG + "," + accentB + ")"
                        var gridCss = String(theme.border)
                        var labelCss = String(theme.mutedText)
                        var baseline = String(theme.text)

                        ctx.lineWidth = 1
                        ctx.font = "12px Sansation"
                        ctx.textAlign = "right"
                        ctx.textBaseline = "middle"

                        // Gridlines are uncovered from the same bottom-left origin as the axes.
                        for (var tick = 0; tick <= root.weeklyYAxisMax; ++tick) {
                            var y = bottom - tick / root.weeklyYAxisMax * graphHeight
                            if (y < visibleTop - 1)
                                continue

                            ctx.beginPath()
                            ctx.strokeStyle = gridCss
                            ctx.globalAlpha = tick === 0 ? 0.72 : 0.42
                            for (var dashX = left; dashX < visibleRight; dashX += 12) {
                                ctx.moveTo(dashX, y)
                                ctx.lineTo(Math.min(visibleRight, dashX + 5), y)
                            }
                            ctx.stroke()
                            ctx.globalAlpha = progress
                            ctx.fillStyle = tick === 0 ? baseline : labelCss
                            ctx.fillText(tick === 0 ? "0 min" : tick + "h", left - 12, y)
                            ctx.globalAlpha = 1
                        }

                        // The vertical and horizontal axes both grow out of (left, bottom).
                        ctx.beginPath()
                        ctx.strokeStyle = baseline
                        ctx.globalAlpha = 0.82
                        ctx.lineWidth = 1.4
                        ctx.moveTo(left, bottom)
                        ctx.lineTo(left, visibleTop)
                        ctx.moveTo(left, bottom)
                        ctx.lineTo(visibleRight, bottom)
                        ctx.stroke()
                        ctx.globalAlpha = 1
                        ctx.lineWidth = 1

                        if (root.historyPeriod === "daily") {
                            // Show the full day scale in 4-hour increments, progressively revealed.
                            ctx.font = "11px Sansation"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "top"
                            ctx.fillStyle = labelCss
                            for (var hourTick = 0; hourTick <= 24; hourTick += 4) {
                                var tickX = left + hourTick / 24 * graphWidth
                                if (tickX > visibleRight + 1)
                                    continue
                                ctx.beginPath()
                                ctx.globalAlpha = 0.32
                                for (var verticalDash = visibleTop; verticalDash < bottom; verticalDash += 12) {
                                    ctx.moveTo(tickX, verticalDash)
                                    ctx.lineTo(tickX, Math.min(bottom, verticalDash + 4))
                                }
                                ctx.strokeStyle = gridCss
                                ctx.stroke()
                                ctx.globalAlpha = progress
                                ctx.fillText(String(hourTick), tickX, bottom + 12)
                                ctx.globalAlpha = 1
                            }
                        }

                        if (pointCount > 0) {
                            // Reveal the polyline a segment at a time from left to right.
                            var travel = progress * (pointCount - 1)
                            var lastFullIndex = Math.min(pointCount - 1, Math.floor(travel))
                            var partialFraction = travel - lastFullIndex
                            var pathPoints = []
                            for (var pathIndex = 0; pathIndex <= lastFullIndex; ++pathIndex) {
                                pathPoints.push({ x: pointX(pathIndex), y: pointY(pathIndex) })
                            }
                            if (lastFullIndex < pointCount - 1 && partialFraction > 0) {
                                var nextX = pointX(lastFullIndex + 1)
                                var nextY = pointY(lastFullIndex + 1)
                                var lastPoint = pathPoints[pathPoints.length - 1]
                                pathPoints.push({
                                    x: lastPoint.x + (nextX - lastPoint.x) * partialFraction,
                                    y: lastPoint.y + (nextY - lastPoint.y) * partialFraction
                                })
                            }

                            // Soft fill follows only the portion of the line that has appeared.
                            if (pathPoints.length > 1) {
                                ctx.beginPath()
                                ctx.moveTo(pathPoints[0].x, bottom)
                                for (var fillIndex = 0; fillIndex < pathPoints.length; ++fillIndex)
                                    ctx.lineTo(pathPoints[fillIndex].x, pathPoints[fillIndex].y)
                                ctx.lineTo(pathPoints[pathPoints.length - 1].x, bottom)
                                ctx.closePath()
                                ctx.fillStyle = "rgba(" + accentR + "," + accentG + "," + accentB + ",0.11)"
                                ctx.fill()
                            }

                            ctx.beginPath()
                            ctx.moveTo(pathPoints[0].x, pathPoints[0].y)
                            for (var lineIndex = 1; lineIndex < pathPoints.length; ++lineIndex)
                                ctx.lineTo(pathPoints[lineIndex].x, pathPoints[lineIndex].y)
                            ctx.strokeStyle = accentCss
                            ctx.lineWidth = 3
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.stroke()

                            // Static markers are painted once per animation frame; hovering never repaints the Canvas.
                            for (var pointIndex = 0; pointIndex <= lastFullIndex; ++pointIndex) {
                                ctx.beginPath()
                                ctx.arc(pointX(pointIndex), pointY(pointIndex), 4.5, 0, Math.PI * 2)
                                ctx.fillStyle = accentCss
                                ctx.fill()
                            }

                            if (progress < 1 && pathPoints.length > 1) {
                                var tip = pathPoints[pathPoints.length - 1]
                                ctx.beginPath()
                                ctx.arc(tip.x, tip.y, 4, 0, Math.PI * 2)
                                ctx.fillStyle = accentCss
                                ctx.fill()
                            }

                            // Numeric day labels for weekly/monthly; hour marks for daily are above.
                            if (root.historyPeriod !== "daily") {
                                ctx.textAlign = "center"
                                ctx.textBaseline = "top"
                                ctx.fillStyle = labelCss
                                ctx.font = root.historyPeriod === "monthly" ? "10px Sansation" : "13px Sansation"
                                ctx.globalAlpha = progress
                                for (var labelIndex = 0; labelIndex <= lastFullIndex; ++labelIndex) {
                                    var dayPoint = root.weeklyFocusPoints[labelIndex]
                                    ctx.fillText(String(dayPoint.label),
                                                 pointX(labelIndex), bottom + 12)
                                }
                                ctx.globalAlpha = 1
                            }
                        }
                    }
                    Connections {
                        target: root
                        function onWeeklyFocusPointsChanged() { historyCanvas.requestPaint() }
                        function onWeeklyYAxisMaxChanged() { historyCanvas.requestPaint() }
                        function onHistoryRevealProgressChanged() { historyCanvas.requestPaint() }
                    }
                    Connections {
                        target: theme
                        function onAccentChanged() { historyCanvas.requestPaint() }
                        function onBorderChanged() { historyCanvas.requestPaint() }
                        function onMutedTextChanged() { historyCanvas.requestPaint() }
                        function onTextChanged() { historyCanvas.requestPaint() }
                    }
                }

                MouseArea {
                    id: historyHoverMouse
                    anchors.fill: parent
                    z: 5
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    enabled: root.historyRevealProgress >= 0.999
                    cursorShape: root.hoveredWeeklyPointIndex >= 0
                                 ? Qt.PointingHandCursor : Qt.ArrowCursor

                    function updateHoveredPoint(mouseX, mouseY) {
                        var nearestIndex = -1
                        var nearestDistanceSquared = 19 * 19
                        for (var i = 0; i < root.weeklyFocusPoints.length; ++i) {
                            var dx = mouseX - historyCanvas.pointX(i)
                            var dy = mouseY - historyCanvas.pointY(i)
                            var distanceSquared = dx * dx + dy * dy
                            if (distanceSquared < nearestDistanceSquared) {
                                nearestDistanceSquared = distanceSquared
                                nearestIndex = i
                            }
                        }
                        // Tooltip follows the selected point; update only when it changes.
                        if (nearestIndex !== root.hoveredWeeklyPointIndex) {
                            root.hoveredWeeklyPointIndex = nearestIndex
                            if (nearestIndex >= 0) {
                                root.historyHoverX = historyCanvas.pointX(nearestIndex)
                                root.historyHoverY = historyCanvas.pointY(nearestIndex)
                            }
                        }
                    }

                    onPositionChanged: function(mouse) {
                        updateHoveredPoint(mouse.x, mouse.y)
                    }
                    onEntered: {
                        updateHoveredPoint(mouseX, mouseY)
                    }
                    onExited: root.hoveredWeeklyPointIndex = -1
                }

                // Hover decoration is pointer-transparent and does not redraw the Canvas.
                Rectangle {
                    id: historyHoveredPointGlow
                    z: 4
                    enabled: false
                    width: 30
                    height: 30
                    radius: 15
                    color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16)
                    border.color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.42)
                    border.width: 1
                    visible: root.hoveredWeeklyPointIndex >= 0 && root.hoveredWeeklyPointIndex < root.weeklyFocusPoints.length
                    x: visible ? historyCanvas.pointX(root.hoveredWeeklyPointIndex) - width / 2 : 0
                    y: visible ? historyCanvas.pointY(root.hoveredWeeklyPointIndex) - height / 2 : 0
                    opacity: visible ? 1 : 0
                }

                Rectangle {
                    id: historyHoveredPointDot
                    z: 6
                    enabled: false
                    width: 16
                    height: 16
                    radius: 8
                    color: theme.accent
                    opacity: root.hoveredWeeklyPointIndex >= 0 ? 1 : 0
                    visible: opacity > 0.01
                    x: visible ? historyCanvas.pointX(root.hoveredWeeklyPointIndex) - width / 2 : 0
                    y: visible ? historyCanvas.pointY(root.hoveredWeeklyPointIndex) - height / 2 : 0
                    Behavior on opacity { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    id: historyHoverTooltip
                    z: 8
                    enabled: false
                    visible: root.hoveredWeeklyPointIndex >= 0
                             && root.hoveredWeeklyPointIndex < root.weeklyFocusPoints.length
                    width: 156
                    height: 58
                    radius: 10
                    color: theme.surfaceRaised
                    border.color: theme.accent
                    border.width: 1
                    x: Math.max(6, Math.min(historyPlot.width - width - 6,
                                             root.historyHoverX - width / 2))
                    y: Math.max(4, root.historyHoverY - height - 14)

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        anchors.topMargin: 9
                        anchors.bottomMargin: 8
                        spacing: 3
                        Text {
                            width: parent.width
                            text: {
                                if (root.hoveredWeeklyPointIndex < 0
                                        || root.hoveredWeeklyPointIndex >= root.weeklyFocusPoints.length)
                                    return ""
                                var point = root.weeklyFocusPoints[root.hoveredWeeklyPointIndex]
                                if (root.historyPeriod === "daily")
                                    return (point.hour < 10 ? "0" : "") + point.hour
                                            + ":00 – " + (point.hour + 1) + ":00"
                                return point.weekday + ", " + point.day
                            }
                            color: theme.mutedText
                            font.pixelSize: 11
                        }
                        Text {
                            width: parent.width
                            text: root.hoveredWeeklyPointIndex >= 0
                                  && root.hoveredWeeklyPointIndex < root.weeklyFocusPoints.length
                                  ? root.formatWeeklyDuration(root.weeklyFocusPoints[root.hoveredWeeklyPointIndex].seconds)
                                  : ""
                            color: theme.text
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
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
            z: -1
            acceptedButtons: Qt.AllButtons
            onClicked: { /* Keep the form open until Add or Cancel is chosen. */ }
        }

        Rectangle {
            id: subjectModal
            anchors.centerIn: parent
            z: 1
            width: Math.min(440, parent.width - 36)
            height: 426
            radius: 18
            color: theme.surfaceRaised
            border.color: theme.border
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 26
                spacing: 10

                Text {
                    text: root.editingSubjectId.length > 0 ? "Edit subject" : "Add a subject"
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
                        id: cancelSubjectEditButton
                        text: "Cancel"
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 42
                        hoverEnabled: true
                        onClicked: root.closeSubjectDialog()
                        background: Rectangle {
                            radius: 9
                            color: cancelSubjectEditButton.hovered ? theme.border : theme.surface
                            border.color: cancelSubjectEditButton.hovered ? theme.accent : theme.border
                            border.width: cancelSubjectEditButton.hovered ? 1.5 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: Text {
                            text: cancelSubjectEditButton.text
                            color: theme.text
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        id: saveSubjectButton
                        text: root.editingSubjectId.length > 0 ? "Save changes" : "Add"
                        Layout.preferredWidth: root.editingSubjectId.length > 0 ? 124 : 100
                        Layout.preferredHeight: 42
                        hoverEnabled: true
                        enabled: root.newSubjectName.trim().length > 0
                                 && root.newSubjectGoal.trim().length > 0
                                 && Number(root.newSubjectGoal) > 0
                        onClicked: root.addSubject()
                        background: Rectangle {
                            radius: 9
                            color: !saveSubjectButton.enabled ? theme.border
                                   : saveSubjectButton.hovered ? Qt.darker(theme.accent, 1.12)
                                   : theme.accent
                            border.color: saveSubjectButton.hovered ? theme.text : theme.accent
                            border.width: saveSubjectButton.hovered ? 1.2 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: Text {
                            text: saveSubjectButton.text
                            color: saveSubjectButton.enabled ? theme.accentText : theme.mutedText
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

    Item {
        id: subjectContextDismissLayer
        anchors.fill: parent
        z: 119
        opacity: root.subjectContextMenuOpen ? 1 : 0
        visible: root.subjectContextMenuOpen || opacity > 0.01
        enabled: root.subjectContextMenuOpen
        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.subjectContextMenuOpen = false
        }
    }

    Rectangle {
        id: subjectContextMenu
        x: root.subjectContextMenuX
        y: root.subjectContextMenuY
        width: 168
        height: 96
        radius: 12
        color: theme.surfaceRaised
        border.color: theme.border
        border.width: 1
        z: 120
        transformOrigin: Item.TopLeft
        scale: root.subjectContextMenuOpen ? 1 : 0.92
        opacity: root.subjectContextMenuOpen ? 1 : 0
        visible: root.subjectContextMenuOpen || opacity > 0.01
        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 4
            z: 1
            Repeater {
                model: [
                    { label: "Edit", action: "edit" },
                    { label: "Delete", action: "delete" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 37
                    radius: 7
                    color: contextActionMouse.containsMouse
                           ? (modelData.action === "delete"
                              ? Qt.rgba(0.82, 0.20, 0.20, 0.16)
                              : Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16))
                           : "transparent"
                    z: 1
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 11
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: modelData.action === "delete" ? "#E06C6C" : theme.text
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: contextActionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var targetId = root.contextMenuSubjectId
                            root.subjectContextMenuOpen = false
                            if (modelData.action === "edit") {
                                root.openEditSubjectDialog(targetId)
                            } else {
                                root.requestSubjectDelete()
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: deleteConfirmReopenTimer
        interval: 190
        repeat: false
        onTriggered: {
            if (root.secondDeleteConfirmationPending) {
                root.secondDeleteConfirmationPending = false
                root.deleteConfirmStage = 2
            }
        }
    }

    Rectangle {
        id: deleteConfirmOverlay
        anchors.fill: parent
        z: 130
        color: "#99000000"
        opacity: root.deleteConfirmStage > 0 ? 1 : 0
        visible: root.deleteConfirmStage > 0 || opacity > 0.01
        enabled: root.deleteConfirmStage > 0 || root.secondDeleteConfirmationPending
        Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.AllButtons
            onClicked: { /* Confirmation remains open until an explicit choice is made. */ }
        }

        Rectangle {
            id: deleteConfirmCard
            anchors.centerIn: parent
            z: 1
            width: Math.min(410, parent.width - 36)
            height: deleteConfirmText.implicitHeight + (root.subjectDeleteError.length > 0 ? 160 : 130)
            radius: 17
            color: theme.surfaceRaised
            border.color: theme.border
            border.width: 1
            scale: root.deleteConfirmStage > 0 ? 1 : 0.94
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

            ColumnLayout {
                id: deleteConfirmText
                anchors.fill: parent
                anchors.margins: 24
                spacing: 11

                Text {
                    Layout.fillWidth: true
                    text: root.deleteConfirmStage === 2 ? "ARE YOU SURE??" : "Are you sure?"
                    color: root.deleteConfirmStage === 2 ? "#F06A6A" : theme.text
                    font.pixelSize: root.deleteConfirmStage === 2 ? 22 : 20
                    font.weight: Font.Bold
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: root.deleteConfirmStage === 2
                          ? "This will permanently delete this subject and cannot be undone."
                          : "Do you really want to delete this subject?"
                    color: theme.mutedText
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.subjectDeleteError.length > 0
                    text: root.subjectDeleteError
                    color: "#F19A9A"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
                Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 9
                    Item { Layout.fillWidth: true }
                    Button {
                        id: cancelDeleteButton
                        text: "Cancel"
                        Layout.preferredWidth: 94
                        Layout.preferredHeight: 40
                        hoverEnabled: true
                        onClicked: root.cancelSubjectDelete()
                        background: Rectangle {
                            radius: 9
                            color: cancelDeleteButton.hovered ? theme.border : theme.surface
                            border.color: cancelDeleteButton.hovered ? theme.accent : theme.border
                            border.width: cancelDeleteButton.hovered ? 1.5 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: Text {
                            text: cancelDeleteButton.text
                            color: theme.text
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        id: confirmDeleteButton
                        text: root.deleteConfirmStage === 2 ? "Delete forever" : "Yes, continue"
                        Layout.preferredWidth: root.deleteConfirmStage === 2 ? 132 : 116
                        Layout.preferredHeight: 40
                        hoverEnabled: true
                        onClicked: root.confirmSubjectDelete()
                        background: Rectangle {
                            radius: 9
                            color: confirmDeleteButton.hovered ? "#B93636" : "#C74747"
                            border.color: confirmDeleteButton.hovered ? "#FF8585" : "#C74747"
                            border.width: confirmDeleteButton.hovered ? 1.5 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: Text {
                            text: confirmDeleteButton.text
                            color: "#FFFFFF"
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
