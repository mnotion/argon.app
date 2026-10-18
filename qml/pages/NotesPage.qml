import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    clip: true
    signal pageSelected(string pageName)

    property var strokes: []
    property var activeStroke: []
    property real zoom: 1.0
    property real documentWidth: 6000
    property real documentHeight: 4500
    property real canvasMargin: 160
    readonly property color workspaceColor: "#1B1B1B"
    readonly property color paperColor: "#252525"
    readonly property color paperBorderColor: "#505050"
    readonly property real minZoom: 0.25
    readonly property real maxZoom: 8.0
    // A modest sensitivity curve makes ordinary finger movement produce
    // a more noticeable zoom without changing the absolute zoom limits.
    readonly property real pinchSensitivity: 1.35

    function clampZoom(value) {
        return Math.max(minZoom, Math.min(maxZoom, value))
    }

    function clampContentX(value) {
        return Math.max(0, Math.min(
            Math.max(0, canvasViewport.contentWidth - canvasViewport.width), value))
    }

    function clampContentY(value) {
        return Math.max(0, Math.min(
            Math.max(0, canvasViewport.contentHeight - canvasViewport.height), value))
    }

    function addDrawingPoint() {
        // The canvas item is sized in zoomed viewport units. Mapping into its
        // local coordinates and dividing by zoom yields stable document units.
        const scenePoint = drawingInput.centroid.scenePosition
        const mapped = drawingCanvas.mapFromItem(null, scenePoint.x, scenePoint.y)
        const documentPoint = Qt.point(mapped.x, mapped.y)

        root.activeStroke.push({ x: documentPoint.x, y: documentPoint.y })
        liveStrokeCanvas.requestPaint()
    }

    function finishStroke() {
        if (root.activeStroke.length > 0) {
            const nextStrokes = root.strokes.slice()
            nextStrokes.push(root.activeStroke)
            root.strokes = nextStrokes
            root.activeStroke = []
            drawingCanvas.requestPaint()
            liveStrokeCanvas.requestPaint()
        }
    }

    function eraseStrokeAtScene(scenePoint) {
        const mapped = drawingCanvas.mapFromItem(null, scenePoint.x, scenePoint.y)
        const eraseRadius = 14 / Math.max(0.25, root.zoom)
        const nextStrokes = []
        let removedAny = false

        for (let s = 0; s < root.strokes.length; ++s) {
            const points = root.strokes[s]
            let hit = false

            for (let p = 0; p < points.length; ++p) {
                const point = points[p]
                const dx = point.x - mapped.x
                const dy = point.y - mapped.y
                if (dx * dx + dy * dy <= eraseRadius * eraseRadius) {
                    hit = true
                    break
                }

                if (p > 0) {
                    const previous = points[p - 1]
                    const vx = point.x - previous.x
                    const vy = point.y - previous.y
                    const lengthSquared = vx * vx + vy * vy
                    const t = lengthSquared > 0
                        ? Math.max(0, Math.min(1, ((mapped.x - previous.x) * vx
                            + (mapped.y - previous.y) * vy) / lengthSquared))
                        : 0
                    const closestX = previous.x + t * vx
                    const closestY = previous.y + t * vy
                    const segmentX = mapped.x - closestX
                    const segmentY = mapped.y - closestY
                    if (segmentX * segmentX + segmentY * segmentY
                            <= eraseRadius * eraseRadius) {
                        hit = true
                        break
                    }
                }
            }

            if (hit)
                removedAny = true
            else
                nextStrokes.push(points)
        }

        if (removedAny) {
            root.strokes = nextStrokes
            drawingCanvas.requestPaint()
        }
    }

    function viewportPointFromScene(scenePoint) {
        return canvasViewport.mapFromItem(null, scenePoint.x, scenePoint.y)
    }

    function zoomAround(nextZoom, anchorX, anchorY, centerX, centerY,
                        oldZoom, oldContentX, oldContentY) {
        // All points are expressed in the viewport's coordinate system.
        // Anchor the original document point beneath the moving pinch centroid.
        const documentX = (oldContentX + anchorX - root.canvasMargin) / oldZoom
        const documentY = (oldContentY + anchorY - root.canvasMargin) / oldZoom

        root.zoom = nextZoom
        canvasViewport.contentX = root.clampContentX(
                    documentX * nextZoom + root.canvasMargin - centerX)
        canvasViewport.contentY = root.clampContentY(
                    documentY * nextZoom + root.canvasMargin - centerY)
    }

    Button {
        id: docsShortcut
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 18
        anchors.rightMargin: 22
        z: 20
        text: "▤"
        implicitWidth: 42
        implicitHeight: 42
        ToolTip.visible: hovered
        ToolTip.text: "Docs"
        flat: true
        onClicked: root.pageSelected("Doc")
        background: Rectangle {
            radius: 10
            color: docsShortcut.hovered ? "#383838" : "#252525"
            border.color: "#505050"
        }
        contentItem: Text {
            text: docsShortcut.text
            color: "#8CBFFF"
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Flickable {
        id: canvasViewport
        anchors.fill: parent
        contentWidth: zoomLayer.width + root.canvasMargin * 2
        contentHeight: zoomLayer.height + root.canvasMargin * 2
        Component.onCompleted: Qt.callLater(function() {
            canvasViewport.contentX = root.clampContentX(
                        (canvasViewport.contentWidth - canvasViewport.width) / 2)
            canvasViewport.contentY = root.clampContentY(
                        (canvasViewport.contentHeight - canvasViewport.height) / 2)
        })
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        interactive: false
        clip: true

        Item {
            id: canvasContent
            x: 0
            y: 0
            width: root.documentWidth * root.zoom + root.canvasMargin * 2
            height: root.documentHeight * root.zoom + root.canvasMargin * 2

            Rectangle {
                anchors.fill: parent
                color: root.workspaceColor
                z: -1
            }

            Item {
                id: zoomLayer
                // Canvas bounds stay inset from the viewport edge, with a darker
                // surrounding workspace visible beyond each document edge.
                x: root.canvasMargin
                y: root.canvasMargin
                width: root.documentWidth * root.zoom
                height: root.documentHeight * root.zoom

                Rectangle {
                    anchors.fill: parent
                    color: root.paperColor
                    border.width: 1
                    border.color: root.paperBorderColor
                    z: -1
                }

                Canvas {
                    id: drawingCanvas
                    width: root.documentWidth
                    height: root.documentHeight
                    scale: root.zoom
                    transformOrigin: Item.TopLeft
                renderTarget: Canvas.FramebufferObject
                antialiasing: true

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.strokeStyle = "#FFFFFF"
                    ctx.lineWidth = 2.6

                    for (let s = 0; s < root.strokes.length; ++s) {
                        const points = root.strokes[s]
                        if (!points || points.length === 0)
                            continue
                        ctx.beginPath()
                        ctx.moveTo(points[0].x, points[0].y)
                        for (let p = 1; p < points.length; ++p)
                            ctx.lineTo(points[p].x, points[p].y)
                        if (points.length === 1)
                            ctx.lineTo(points[0].x + 0.1, points[0].y + 0.1)
                        ctx.stroke()
                    }

                }

                }
            }
        }
    }

    // Keep live ink in a viewport-sized layer. Repainting a 6000x4500 canvas
    // for every pointer event causes severe input lag even when only one stroke changes.
    Canvas {
        id: liveStrokeCanvas
        anchors.fill: parent
        z: 10
        renderTarget: Canvas.FramebufferObject
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.strokeStyle = "#FFFFFF"
            ctx.lineWidth = 2.6 * root.zoom

            if (root.activeStroke.length > 0) {
                const first = root.activeStroke[0]
                ctx.beginPath()
                ctx.moveTo(first.x * root.zoom + root.canvasMargin - canvasViewport.contentX,
                           first.y * root.zoom + root.canvasMargin - canvasViewport.contentY)
                for (let p = 1; p < root.activeStroke.length; ++p) {
                    const point = root.activeStroke[p]
                    ctx.lineTo(point.x * root.zoom + root.canvasMargin - canvasViewport.contentX,
                               point.y * root.zoom + root.canvasMargin - canvasViewport.contentY)
                }
                if (root.activeStroke.length === 1)
                    ctx.lineTo(first.x * root.zoom + root.canvasMargin - canvasViewport.contentX + 0.1,
                               first.y * root.zoom + root.canvasMargin - canvasViewport.contentY + 0.1)
                ctx.stroke()
            }
        }
    }

    // Keep gesture handlers in the viewport's coordinate space, not inside
    // Flickable's moving content item.
    DragHandler {
        id: drawingInput
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus
        acceptedPointerTypes: PointerDevice.Generic | PointerDevice.Pen
        dragThreshold: 0

        onActiveChanged: {
            if (active) {
                root.activeStroke = []
                root.addDrawingPoint()
            } else {
                root.finishStroke()
            }
        }

        onCentroidChanged: {
            if (active)
                root.addDrawingPoint()
        }
    }

    // Route the dedicated eraser tip separately from the normal pen tip.
    // Some tablets report the barrel/side button as a right-button press too.
    DragHandler {
        id: stylusEraseInput
        target: null
        acceptedDevices: PointerDevice.Stylus
        acceptedPointerTypes: PointerDevice.Eraser
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        dragThreshold: 0

        onActiveChanged: {
            if (active)
                root.eraseStrokeAtScene(centroid.scenePosition)
        }

        onCentroidChanged: {
            if (active)
                root.eraseStrokeAtScene(centroid.scenePosition)
        }
    }

    PinchHandler {
        id: pinchHandler
        target: null
        acceptedDevices: PointerDevice.TouchScreen
        // This handler reports gesture-relative scale; root.zoom applies the document limits.
        minimumScale: 0.01
        maximumScale: 100.0
        minimumPointCount: 2
        maximumPointCount: 2

        property real previousGestureScale: 1
        property point previousCenter

        function updatePinch() {
            if (!active)
                return

            // Apply only the change since the previous event. This avoids
            // mixing a gesture-start scale/centroid with a later centroid,
            // which caused jumps when Qt updated the two values separately.
            const center = root.viewportPointFromScene(centroid.scenePosition)
            const rawScaleRatio = scale / Math.max(0.0001, previousGestureScale)
            const scaleRatio = Math.pow(Math.max(0.01, rawScaleRatio),
                                        root.pinchSensitivity)
            const oldZoom = root.zoom
            const nextZoom = root.clampZoom(oldZoom * scaleRatio)

            const documentX = (canvasViewport.contentX + previousCenter.x
                               - root.canvasMargin) / oldZoom
            const documentY = (canvasViewport.contentY + previousCenter.y
                               - root.canvasMargin) / oldZoom

            root.zoom = nextZoom
            canvasViewport.contentX = root.clampContentX(
                        documentX * nextZoom + root.canvasMargin - center.x)
            canvasViewport.contentY = root.clampContentY(
                        documentY * nextZoom + root.canvasMargin - center.y)

            previousGestureScale = scale
            previousCenter = center
        }

        onActiveChanged: {
            if (active) {
                previousGestureScale = scale
                previousCenter = root.viewportPointFromScene(centroid.scenePosition)
            }
        }

        onScaleChanged: updatePinch()
        onCentroidChanged: updatePinch()
    }

    DragHandler {
        id: touchPanHandler
        target: null
        acceptedDevices: PointerDevice.TouchScreen
        dragThreshold: 8
        maximumPointCount: 1

        property point lastTranslation

        onActiveChanged: {
            if (active)
                lastTranslation = translation
        }

        onTranslationChanged: {
            if (!active)
                return
            const dx = translation.x - lastTranslation.x
            const dy = translation.y - lastTranslation.y
            lastTranslation = translation
            canvasViewport.contentX = root.clampContentX(canvasViewport.contentX - dx)
            canvasViewport.contentY = root.clampContentY(canvasViewport.contentY - dy)
        }
    }
}

