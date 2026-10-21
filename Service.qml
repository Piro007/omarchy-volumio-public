import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
    id: root
    property var shell: null
    property var manifest: null
    property bool online: false
    property bool connecting: true
    property bool ready: false
    property bool stopping: false
    property bool autoStart: true
    property var snapshot: ({})
    property string address: "http://volumio.local"
    property string savedAddress: "http://volumio.local"
    onShellChanged: if (shell) configure(Model.addressFromBar(shell.barConfig))
    property string lastError: ""
    property int sequence: 0
    property int pendingSave: -1
    property int pendingCommand: -1
    property int pendingVolume: -1
    property int desiredVolume: -1
    readonly property bool busy: pendingCommand >= 0
    readonly property string binaryPath: decodeURIComponent(Qt.resolvedUrl("bin/omarchy-volumio").toString().replace(/^file:\/\//, ""))

    function send(op, fields) {
        if (!ready) return -1;
        var request = fields || {};
        request.id = ++sequence;
        request.op = op;
        backend.write(JSON.stringify(request) + "\n");
        return request.id;
    }
    function configure(value) {
        value = String(value || "http://volumio.local");
        savedAddress = value;
        if (value.replace(/\/$/, "") === address.replace(/\/$/, "")) return;
        address = value;
        if (ready) send("configure", {address: address});
    }
    function saveAddress(value) {
        if (!ready) { lastError = "Backend unavailable"; return; }
        pendingSave = send("configure", {address: String(value).trim()});
    }
    function refresh() { send("refresh"); }
    function receiveConfig(line) {
        try {
            const config = JSON.parse(line);
            if (!config.bar || !config.bar.layout) throw new Error("Missing bar configuration");
            configure(Model.addressFromBar(config.bar));
        } catch (e) { lastError = "Could not read saved Omarchy configuration"; }
    }
    function action(op) {
        if (!online || busy) return;
        lastError = "";
        pendingCommand = send(op);
    }
    function setVolume(value, finalValue) {
        if (!online || snapshot.disableVolumeControl) return;
        desiredVolume = Math.max(0, Math.min(100, Math.round(value)));
        if (finalValue) { volumeTimer.stop(); flushVolume(); }
        else volumeTimer.restart();
    }
    function flushVolume() {
        if (desiredVolume < 0 || pendingVolume >= 0 || !online) return;
        var value = desiredVolume;
        desiredVolume = -1;
        pendingVolume = send("volume", {volume: value});
    }
    function receive(line) {
        var event;
        try { event = JSON.parse(line); } catch (e) { lastError = "Invalid backend response"; return; }
        if (event.type === "ready") {
            startupTimer.stop();
            if (event.protocol !== 1) {
                lastError = "Unsupported backend protocol; rebuild the installed plugin.";
                return;
            }
            ready = true;
            send("configure", {address: savedAddress});
            if (autoStart) configReader.running = true;
        } else if (event.type === "configured") {
            address = event.address;
            snapshot = ({});
            desiredVolume = -1;
            lastError = "";
            if (event.id === pendingSave) {
                pendingSave = -1;
                if (savedAddress.replace(/\/$/, "") !== address.replace(/\/$/, "")) {
                    if (shell && shell.updateEntryInline("delormous.volumio", {address: address}))
                        savedAddress = address;
                    else lastError = "Could not save the address in Omarchy";
                }
            }
        } else if (event.type === "state") {
            snapshot = event.state;
            online = true;
            connecting = false;
        } else if (event.type === "connection") {
            online = false;
            connecting = event.connecting === true;
            desiredVolume = -1;
            volumeTimer.stop();
        } else if (event.type === "result") {
            if (event.id === pendingCommand) pendingCommand = -1;
            if (event.id === pendingSave) pendingSave = -1;
            if (event.id === pendingVolume) {
                pendingVolume = -1;
                if (event.ok) flushVolume();
                else desiredVolume = -1;
            }
            if (!event.ok) lastError = String(event.error || "Command failed");
        }
    }
    function failed() {
        ready = false; online = false; connecting = false;
        pendingSave = -1; pendingCommand = -1; pendingVolume = -1; desiredVolume = -1;
        volumeTimer.stop();
        startupTimer.stop();
        lastError = "Backend unavailable. Retrying in 3 s; build the installed plugin if this persists.";
        if (autoStart && !stopping) restartTimer.restart();
    }

    function startBackend() {
        if (stopping || backend.running) return;
        startupTimer.restart();
        backend.running = true;
    }
    Component.onCompleted: if (autoStart) startBackend()
    Component.onDestruction: { stopping = true; restartTimer.stop(); startupTimer.stop(); configTimer.stop(); configReader.running = false; backend.running = false; }
    Timer { id: volumeTimer; interval: 150; onTriggered: root.flushVolume() }
    Timer { id: restartTimer; interval: 3000; onTriggered: root.startBackend() }
    // Host plugin facades can retain old snapshots across a rescan. Read the
    // current configuration through official IPC when a backend starts.
    Timer {
        id: configTimer
        interval: 5000
        onTriggered: {
            configReader.running = false;
            root.lastError = "Timed out reading saved Omarchy configuration";
        }
    }
    Process {
        id: configReader
        command: ["omarchy-shell", "shell", "listShellConfig"]
        stdout: SplitParser { onRead: function(line) { root.receiveConfig(line); } }
        onRunningChanged: if (running) configTimer.restart(); else configTimer.stop()
        onExited: function(code) {
            if (code !== 0 && !root.stopping) root.lastError = "Could not read saved Omarchy configuration";
        }
    }
    // Process may fail before emitting exited (for example, a missing binary).
    Timer {
        id: startupTimer
        interval: 5000
        onTriggered: if (!root.ready) { backend.running = false; root.failed(); }
    }
    Process {
        id: backend
        command: [root.binaryPath]
        stdinEnabled: true
        stdout: SplitParser { onRead: function(line) { root.receive(line); } }
        stderr: SplitParser { onRead: function(line) { console.warn("Volumio:", line); } }
        onExited: root.failed()
        onRunningChanged: if (!running && !root.stopping && root.autoStart) root.failed()
    }
    IpcHandler {
        target: "delormous.volumio"
        function status(): string { return JSON.stringify({online: root.online, address: root.address, savedAddress: root.savedAddress, backendPid: backend.processId, panelOpen: root.shell ? root.shell.isPluginOpen("delormous.volumio") : false, state: root.snapshot, error: root.lastError}); }
        function refresh(): void { root.refresh(); }
        function configure(address: string): void { root.saveAddress(address); }
        function action(command: string): void { root.action(command); }
        function volume(value: int): void { root.setVolume(value, true); }
    }
}
