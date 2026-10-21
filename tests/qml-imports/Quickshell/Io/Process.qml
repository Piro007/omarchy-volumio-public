import QtQuick
QtObject {
    property var command: []
    property bool running: false
    property bool stdinEnabled: false
    property var stdout: null
    property var stderr: null
    property int processId: running ? 123 : 0
    signal exited(int exitCode, int exitStatus)
    function write(data) { Harness.requests = Harness.requests.concat([JSON.parse(data)]); }
    onRunningChanged: if (running && stdinEnabled) Harness.starts++
    Component.onCompleted: if (stdinEnabled) Harness.process = this
}
