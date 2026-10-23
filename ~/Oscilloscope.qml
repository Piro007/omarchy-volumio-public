import QtQuick
import "Model.js" as Model

// Small decorative oscilloscope for the bar. Volumio's REST state exposes no
// audio levels, so this animation follows playback status rather than sound:
// it scrolls and morphs while playing, freezes on pause and flattens when the
// player is stopped or unreachable.
Item {
    id: root

    property color foreground: "#ffffff"
    property bool running: false
    property bool active: true
    property bool showFrame: true
    property real cornerRadius: 3
    property real traceWidth: 1.2
    property real cycles: 1.5
    property real speed: 3.6
    property real holdSeconds: 2.6
    property real morphSeconds: 1.4
    property real amplitudeScale: 0.42

    property real phase: 0
    property real morphClock: 0
    property real lastTick: 0

    readonly property real cycleSeconds: holdSeconds + morphSeconds
    readonly property int shapeIndex: Math.floor(morphClock / cycleSeconds) % 4
    readonly property real shapeMix: {
        var t = morphClock - Math.floor(morphClock / cycleSeconds) * cycleSeconds;
        if (t <= holdSeconds) return 0;
        return Model.smoothstep((t - holdSeconds) / morphSeconds);
    }

    function shapeAt(index) {
        return ["sine", "saw", "square", "triangle"][((index % 4) + 4) % 4];
    }

    function advance() {
        var now = Date.now();
        var dt = lastTick > 0 ? Math.min(0.12, (now - lastTick) / 1000) : 0.033;
        lastTick = now;
        phase += dt * speed;
        morphClock += dt;
        canvas.requestPaint();
    }

    onRunningChanged: {
        lastTick = 0;
        if (!running) canvas.requestPaint();
    }
    onActiveChanged: canvas.requestPaint()
    onForegroundChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()

    Timer {
        interval: 33
        repeat: true
        running: root.running && root.visible
        onTriggered: root.advance()
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        visible: root.showFrame
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)
        radius: root.cornerRadius
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 2
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            var w = width;
            var h = height;
            ctx.clearRect(0, 0, w, h);
            if (w < 2 || h < 2) return;

            var mid = h / 2;
            var amplitude = root.active ? h * root.amplitudeScale : 0;
            var from = root.shapeAt(root.shapeIndex);
            var to = root.shapeAt(root.shapeIndex + 1);
            var mix = root.shapeMix;

            ctx.strokeStyle = root.foreground;
            ctx.lineWidth = 1;
            ctx.globalAlpha = 0.18;
            ctx.beginPath();
            ctx.moveTo(0, mid);
            ctx.lineTo(w, mid);
            ctx.stroke();

            ctx.globalAlpha = root.active ? 0.95 : 0.45;
            ctx.lineWidth = root.traceWidth;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.beginPath();
            var samples = Math.max(24, Math.ceil(w * 2));
            for (let i = 0; i <= samples; ++i) {
                const x = w * i / samples;
                const phase = root.phase + (i / samples) * root.cycles * Math.PI * 2;
                const y = mid - Model.blendWave(from, to, phase, mix) * amplitude;
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.stroke();
            ctx.globalAlpha = 1;
        }
    }
}
