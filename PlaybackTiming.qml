import QtQuick
import "Model.js" as Model

// Confirmed snapshots only: this display never seeks or extrapolates time.
Column {
    id: root
    property var snapshot: ({})
    property bool online: false
    property color foreground: "white"
    property string fontFamily: "sans-serif"
    property int fontSize: 12
    property int trackHeight: 3
    readonly property bool hasSeek: Model.validTime(snapshot.seek)
    readonly property bool hasDuration: Model.validTime(snapshot.duration) && snapshot.duration > 0
    readonly property bool progressVisible: hasSeek && hasDuration
    readonly property real fraction: progressVisible ? Math.max(0, Math.min(1, snapshot.seek / 1000 / snapshot.duration)) : 0
    readonly property string timeText: Model.formatTime(hasSeek ? snapshot.seek / 1000 : null)
        + " / " + Model.formatTime(hasDuration ? snapshot.duration : null)
    opacity: online ? 1 : 0.5
    spacing: 4
    Text {
        width: parent.width
        text: root.timeText
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        elide: Text.ElideRight
        Accessible.role: Accessible.StaticText
        Accessible.name: "Playback time: " + text
    }
    Rectangle {
        width: parent.width
        height: root.trackHeight
        radius: height / 2
        visible: root.progressVisible
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
        Rectangle {
            width: parent.width * root.fraction
            height: parent.height
            radius: height / 2
            color: root.foreground
        }
    }
}
