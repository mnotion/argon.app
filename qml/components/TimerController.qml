import QtQml

QtObject {
    id: root

    property bool timerRunning: false
    property real elapsedMilliseconds: 0
    property real lastTickAt: 0
    property real focusedRemainderMilliseconds: 0
    property string statusMessage: ""
    property string activeSubjectId: ""
    property var subjectElapsedMilliseconds: ({})
    property var subjectMonthlyElapsedMilliseconds: ({})

    function monthKeyForTimestamp(timestamp) {
        var date = new Date(timestamp)
        var month = date.getMonth() + 1
        return date.getFullYear() + "-" + (month < 10 ? "0" : "") + month
    }

    function addSubjectElapsedInterval(subjectId, startTimestamp, endTimestamp) {
        var elapsed = Math.max(0, endTimestamp - startTimestamp)
        if (subjectId.length === 0 || elapsed <= 0)
            return

        var lifetimeTotals = {}
        var lifetimeKeys = Object.keys(subjectElapsedMilliseconds || ({}))
        for (var i = 0; i < lifetimeKeys.length; ++i)
            lifetimeTotals[lifetimeKeys[i]] = Number(subjectElapsedMilliseconds[lifetimeKeys[i]]) || 0

        var monthlyTotals = {}
        var monthlyKeys = Object.keys(subjectMonthlyElapsedMilliseconds || ({}))
        for (var j = 0; j < monthlyKeys.length; ++j)
            monthlyTotals[monthlyKeys[j]] = Number(subjectMonthlyElapsedMilliseconds[monthlyKeys[j]]) || 0

        var id = String(subjectId)
        lifetimeTotals[id] = Math.max(0, Number(lifetimeTotals[id]) || 0) + elapsed

        // Split an interval at month boundaries so time crossing midnight on the
        // last day of a month is credited to the correct calendar month.
        var cursor = startTimestamp
        while (cursor < endTimestamp) {
            var monthStartDate = new Date(cursor)
            var nextMonth = new Date(monthStartDate.getFullYear(),
                                     monthStartDate.getMonth() + 1, 1).getTime()
            var segmentEnd = Math.min(endTimestamp, nextMonth)
            var key = monthKeyForTimestamp(cursor) + "|" + id
            monthlyTotals[key] = Math.max(0, Number(monthlyTotals[key]) || 0)
                    + Math.max(0, segmentEnd - cursor)
            cursor = segmentEnd
        }

        subjectElapsedMilliseconds = lifetimeTotals
        subjectMonthlyElapsedMilliseconds = monthlyTotals
    }

    function formattedTime() {
        var totalMinutes = Math.floor(elapsedMilliseconds / 60000)
        var hours = Math.floor(totalMinutes / 60)
        var minutes = totalMinutes % 60
        return (hours < 10 ? "0" : "") + hours + ":" +
               (minutes < 10 ? "0" : "") + minutes
    }

    function resetTimer() {
        if (timerRunning)
            tick()

        timerRunning = false
        elapsedMilliseconds = 0
        focusedRemainderMilliseconds = 0
        lastTickAt = Date.now()
        statusMessage = ""
        persistElapsedState()
    }

    function persistElapsedState() {
        // Capture the current tick before an update or shutdown so the last
        // fraction of a second is not lost in the handoff.
        if (timerRunning)
            tick()

        // The stopwatch is user state, not transient UI state. Keep it outside
        // the replaceable App directory so application updates cannot reset it.
        var elapsedSaved = appSettingsService.setValue(
                    "timer.elapsedMilliseconds",
                    Math.max(0, Math.floor(elapsedMilliseconds)))
        var runningSaved = appSettingsService.setValue(
                    "timer.wasRunning", timerRunning)
        var subjectIdSaved = appSettingsService.setValue(
                    "timer.activeSubjectId", activeSubjectId)
        var subjectTimesSaved = appSettingsService.setValue(
                    "timer.subjectElapsedMilliseconds", subjectElapsedMilliseconds)
        var monthlyTimesSaved = appSettingsService.setValue(
                    "timer.subjectMonthlyElapsedMilliseconds", subjectMonthlyElapsedMilliseconds)
        if (!elapsedSaved || !runningSaved || !subjectIdSaved
                || !subjectTimesSaved || !monthlyTimesSaved)
            console.warn("[TimerPersistence] Could not save stopwatch state; check the settings-path diagnostics in argon-runtime.log.")
        return elapsedSaved && runningSaved && subjectIdSaved
                && subjectTimesSaved && monthlyTimesSaved
    }

    function toggleTimer() {
        if (timerRunning) {
            tick()
            timerRunning = false
            statusMessage = "Paused."
            persistElapsedState()
            return
        }

        timerRunning = true
        lastTickAt = Date.now()
        statusMessage = ""
        persistElapsedState()
    }

    function tick() {
        var now = Date.now()
        dailyAnalyticsService.refreshToday()

        if (!timerRunning) {
            lastTickAt = now
            return
        }

        var intervalStart = lastTickAt
        var elapsed = Math.max(0, now - intervalStart)
        lastTickAt = now
        if (elapsed <= 0)
            return

        elapsedMilliseconds += elapsed

        // Store both lifetime subject time and a separately keyed calendar-month
        // total. The monthly map drives subject ordering in the Timer page.
        if (activeSubjectId.length > 0)
            addSubjectElapsedInterval(activeSubjectId, intervalStart, now)

        // Count only whole elapsed seconds in the daily analytics record.
        var accumulated = focusedRemainderMilliseconds + elapsed
        var wholeSeconds = Math.floor(accumulated / 1000)
        focusedRemainderMilliseconds = accumulated - wholeSeconds * 1000
        if (wholeSeconds > 0) {
            var focusSubjectId = String(activeSubjectId)
            if (focusSubjectId.length > 0) {
                var focusSubjectName = focusSubjectId
                var focusSubjectColour = "#8CBFFF"
                var storedSubjects = appSettingsService.value("timer.subjects", [])
                if (storedSubjects && storedSubjects.length !== undefined) {
                    for (var subjectIndex = 0; subjectIndex < storedSubjects.length; ++subjectIndex) {
                        var subject = storedSubjects[subjectIndex]
                        if (String(subject.id) === focusSubjectId) {
                            focusSubjectName = String(subject.name || focusSubjectId)
                            focusSubjectColour = String(subject.colour || focusSubjectColour)
                            break
                        }
                    }
                }
                dailyAnalyticsService.addFocusedSeconds(
                            wholeSeconds, focusSubjectId,
                            focusSubjectName, focusSubjectColour)
            } else {
                dailyAnalyticsService.addFocusedSeconds(wholeSeconds)
            }
        }
    }

    Component.onCompleted: {
        // Restore accumulated time and the previous running state. Restart the
        // clock from now so time spent closed or updating is not counted.
        var savedElapsed = Number(appSettingsService.value(
                                     "timer.elapsedMilliseconds", 0))
        if (isFinite(savedElapsed) && savedElapsed >= 0)
            elapsedMilliseconds = savedElapsed

        activeSubjectId = String(appSettingsService.value("timer.activeSubjectId", ""))
        var storedSubjectTimes = appSettingsService.value("timer.subjectElapsedMilliseconds", ({}))
        subjectElapsedMilliseconds = storedSubjectTimes && typeof storedSubjectTimes === "object"
                ? storedSubjectTimes : ({})
        var storedMonthlyTimes = appSettingsService.value("timer.subjectMonthlyElapsedMilliseconds", ({}))
        subjectMonthlyElapsedMilliseconds = storedMonthlyTimes && typeof storedMonthlyTimes === "object"
                ? storedMonthlyTimes : ({})

        // Resume only if the stopwatch was running when Argon last saved state.
        // lastTickAt is reset first so time spent updating/restarting is not counted.
        lastTickAt = Date.now()
        timerRunning = Boolean(appSettingsService.value("timer.wasRunning", false))
        dailyAnalyticsService.refreshToday()
        console.info("[TimerPersistence] Restored stopwatch state:",
                    Math.floor(elapsedMilliseconds), "ms; running:", timerRunning,
                    "| today's focus:", dailyAnalyticsService.focusedSecondsToday, "seconds")
    }

    property Timer persistenceClock: Timer {
        // Avoid synchronous disk commits on the UI thread every second. The
        // update/install and pause/close paths also save immediately.
        interval: 5000
        repeat: true
        running: root.timerRunning
        onTriggered: root.persistElapsedState()
    }

    property Timer clock: Timer {
        interval: 200
        repeat: true
        running: true
        onTriggered: root.tick()
    }
}
