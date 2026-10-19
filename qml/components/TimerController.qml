import QtQml

QtObject {
    id: root

    property bool timerRunning: false
    property real elapsedMilliseconds: 0
    property real lastTickAt: 0
    property real focusedRemainderMilliseconds: 0
    property string statusMessage: ""

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
        if (!elapsedSaved || !runningSaved)
            console.warn("[TimerPersistence] Could not save stopwatch state; check the settings-path diagnostics in argon-runtime.log.")
        return elapsedSaved && runningSaved
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

        var elapsed = Math.max(0, now - lastTickAt)
        lastTickAt = now
        if (elapsed <= 0)
            return

        elapsedMilliseconds += elapsed

        // Count only whole elapsed seconds in the daily analytics record.
        var accumulated = focusedRemainderMilliseconds + elapsed
        var wholeSeconds = Math.floor(accumulated / 1000)
        focusedRemainderMilliseconds = accumulated - wholeSeconds * 1000
        if (wholeSeconds > 0)
            dailyAnalyticsService.addFocusedSeconds(wholeSeconds)
    }

    Component.onCompleted: {
        // Restore accumulated time and the previous running state. Restart the
        // clock from now so time spent closed or updating is not counted.
        var savedElapsed = Number(appSettingsService.value(
                                     "timer.elapsedMilliseconds", 0))
        if (isFinite(savedElapsed) && savedElapsed >= 0)
            elapsedMilliseconds = savedElapsed

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
