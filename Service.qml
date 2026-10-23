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
    property string iconMode: "cover"
    property string savedIconMode: "cover"
    onShellChanged: if (shell) {
        configure(Model.addressFromBar(shell.barConfig));
        syncIconMode(Model.iconModeFromBar(shell.barConfig));
    }
    property string lastError: ""
    property int sequence: 0
    property int pendingSave: -1
    property int pendingCommand: -1
    property int pendingVolume: -1
    property int desiredVolume: -1
    property int targetVolume: -1
    property bool volumeFinal: false
    readonly property int effectiveVolume: targetVolume >= 0 ? targetVolume : (typeof snapshot.volume === "number" ? snapshot.volume : 0)
    property bool supportsLibrary: false
    property alias albums: albumModel
    property int browseId: -1
    property bool albumsComplete: false
    property string libraryError: ""
    property string albumError: ""
    property int pendingAlbum: -1
    property string activatingAlbum: ""
    property bool supportsPlaylists: false
    property alias playlists: playlistModel
    property int playlistBrowseId: -1
    property bool playlistsComplete: false
    property string playlistError: ""
    property int pendingPlaylist: -1
    property string activatingPlaylist: ""
    readonly property bool browsing: browseId >= 0
    readonly property bool browsingPlaylists: playlistBrowseId >= 0
    readonly property bool busy: pendingCommand >= 0 || pendingAlbum >= 0 || pendingPlaylist >= 0
    ListModel { id: albumModel }
    ListModel { id: playlistModel }
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
        clearVolume();
        address = value;
        if (ready) send("configure", {address: address});
    }
    function saveAddress(value) {
        if (!ready) { lastError = "Backend unavailable"; return; }
        clearVolume();
        pendingSave = send("configure", {address: String(value).trim()});
    }
    // Coerces the stored value to one of the two supported modes.
    function applyIconMode(mode) {
        iconMode = mode === "scope" ? "scope" : "cover";
    }
    // An externally persisted change (settings or listShellConfig) is already
    // in shell.json, so the saved value must follow it.
    function syncIconMode(mode) {
        applyIconMode(mode);
        savedIconMode = iconMode;
    }
    // updateEntryInline replaces the whole layout entry, so every write carries
    // the other widget settings as well.
    function setIconMode(mode) {
        applyIconMode(mode);
        if (!shell || savedIconMode === iconMode) return false;
        if (!shell.updateEntryInline("delormous.volumio", {address: savedAddress, barIcon: iconMode})) {
            lastError = "Could not save the bar icon mode in Omarchy";
            return false;
        }
        savedIconMode = iconMode;
        return true;
    }
    function toggleIconMode() { setIconMode(iconMode === "cover" ? "scope" : "cover"); }
    function refresh() { send("refresh"); }
    function browseAlbums(force) {
        if (!ready || !supportsLibrary) {
            libraryError = "Album browsing requires the updated backend. Build the installed plugin.";
            return;
        }
        if (!force && (albumsComplete || browsing)) return;
        cancelBrowse();
        albumModel.clear();
        albumsComplete = false;
        libraryError = "";
        browseId = send("browse_albums");
    }
    function cancelBrowse() {
        if (browsing || browsingPlaylists) send("cancel_browse");
        browseId = -1;
        playlistBrowseId = -1;
    }
    function browsePlaylists(force) {
        if (!ready || !supportsPlaylists) {
            playlistError = "Playlist browsing requires the updated backend. Build the installed plugin.";
            return;
        }
        if (!force && (playlistsComplete || browsingPlaylists)) return;
        cancelBrowse();
        playlistModel.clear();
        playlistsComplete = false;
        playlistError = "";
        playlistBrowseId = send("browse_playlists");
    }
    function playPlaylist(name) {
        if (!online || busy || !supportsPlaylists) return;
        playlistError = "";
        activatingPlaylist = name;
        pendingPlaylist = send("play_playlist", {name: name});
    }
    function clearLibrary() {
        browseId = -1;
        albumsComplete = false;
        albumModel.clear();
        libraryError = "";
        if (pendingAlbum >= 0)
            albumError = "Album activation interrupted; check the player before retrying.";
        pendingAlbum = -1;
        activatingAlbum = "";
        playlistBrowseId = -1;
        playlistsComplete = false;
        playlistModel.clear();
        playlistError = pendingPlaylist >= 0 ? "Playlist activation interrupted; check the player before retrying." : "";
        pendingPlaylist = -1;
        activatingPlaylist = "";
    }
    function playAlbum(uri) {
        if (!online || busy || !supportsLibrary) return;
        albumError = "";
        activatingAlbum = uri;
        pendingAlbum = send("play_album", {uri: uri});
    }
    function receiveConfig(line) {
        try {
            const config = JSON.parse(line);
            if (!config.bar || !config.bar.layout) throw new Error("Missing bar configuration");
            configure(Model.addressFromBar(config.bar));
            syncIconMode(Model.iconModeFromBar(config.bar));
        } catch (e) { lastError = "Could not read saved Omarchy configuration"; }
    }
    function action(op) {
        if (!online || busy) return;
        lastError = "";
        pendingCommand = send(op);
    }
    function setVolume(value, finalValue) {
        if (!ready || !online || snapshot.disableVolumeControl || typeof snapshot.volume !== "number" || !isFinite(value)) return;
        var next = Math.max(0, Math.min(100, Math.round(value)));
        // Release/wheel can repeat the value already submitted by moved().
        if (next === targetVolume && desiredVolume < 0) return;
        desiredVolume = next;
        targetVolume = desiredVolume;
        volumeFinal = finalValue;
        volumeConfirmTimer.stop();
        if (finalValue) volumeTimer.stop();
        if (!volumeTimer.running) flushVolume();
    }
    function adjustVolume(delta) {
        setVolume(effectiveVolume + delta, true);
    }
    function clearVolume() {
        pendingVolume = -1;
        desiredVolume = -1;
        targetVolume = -1;
        volumeFinal = false;
        volumeTimer.stop();
        volumeConfirmTimer.stop();
    }
    function flushVolume() {
        if (desiredVolume < 0 || pendingVolume >= 0 || !ready || !online || snapshot.disableVolumeControl) return;
        var value = desiredVolume;
        desiredVolume = -1;
        pendingVolume = send("volume", {volume: value});
        volumeTimer.restart();
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
            supportsLibrary = Array.isArray(event.features) && event.features.indexOf("albums") >= 0;
            supportsPlaylists = Array.isArray(event.features) && event.features.indexOf("playlists") >= 0;
            ready = true;
            send("configure", {address: savedAddress});
            if (autoStart) configReader.running = true;
        } else if (event.type === "configured") {
            clearLibrary();
            address = event.address;
            snapshot = ({});
            clearVolume();
            lastError = "";
            if (event.id === pendingSave) {
                pendingSave = -1;
                if (savedAddress.replace(/\/$/, "") !== address.replace(/\/$/, "")) {
                    if (shell && shell.updateEntryInline("delormous.volumio", {address: address, barIcon: iconMode})) {
                        savedAddress = address;
                        savedIconMode = iconMode;
                    } else lastError = "Could not save the address in Omarchy";
                }
            }
        } else if (event.type === "albums" && event.id === browseId) {
            const items = event.items || [];
            for (let i = 0; i < items.length; ++i)
                albumModel.append({uri: String(items[i].uri), title: String(items[i].title), albumart: String(items[i].albumart || "")});
            if (event.done) { browseId = -1; albumsComplete = true; }
        } else if (event.type === "playlists" && event.id === playlistBrowseId) {
            const items = event.items || [];
            for (let i = 0; i < items.length; ++i)
                playlistModel.append({name: String(items[i].name)});
            if (event.done) { playlistBrowseId = -1; playlistsComplete = true; }
        } else if (event.type === "library_error" && event.id === playlistBrowseId) {
            playlistBrowseId = -1;
            playlistError = String(event.error || "Could not load playlists");
        } else if (event.type === "library_error" && event.id === browseId) {
            browseId = -1;
            libraryError = String(event.error || "Could not load albums");
        } else if (event.type === "state") {
            snapshot = event.state;
            if (snapshot.disableVolumeControl || typeof snapshot.volume !== "number") clearVolume();
            else if (pendingVolume < 0 && desiredVolume < 0 && snapshot.volume === targetVolume) {
                targetVolume = -1;
                volumeConfirmTimer.stop();
            }
            online = true;
            connecting = false;
        } else if (event.type === "connection") {
            online = false;
            connecting = event.connecting === true;
            clearVolume();
        } else if (event.type === "result") {
            if (event.id === pendingPlaylist) {
                pendingPlaylist = -1;
                activatingPlaylist = "";
                if (!event.ok) playlistError = String(event.error || "Playlist activation failed");
                refresh();
                return;
            }
            if (event.id === pendingAlbum) {
                pendingAlbum = -1;
                activatingAlbum = "";
                if (!event.ok) albumError = String(event.error || "Album activation failed");
                refresh();
                return;
            }
            if (event.id === pendingCommand) pendingCommand = -1;
            if (event.id === pendingSave) pendingSave = -1;
            if (event.id === pendingVolume) {
                pendingVolume = -1;
                if (event.ok) {
                    if (volumeFinal || !volumeTimer.running) flushVolume();
                    if (pendingVolume < 0 && desiredVolume < 0) volumeConfirmTimer.restart();
                } else clearVolume();
            }
            if (!event.ok) lastError = String(event.error || "Command failed");
        }
    }
    function failed() {
        ready = false; online = false; connecting = false;
        supportsLibrary = false;
        supportsPlaylists = false;
        clearLibrary();
        libraryError = "Backend unavailable. Reopen the browser after reconnection.";
        playlistError = "Backend unavailable. Reopen the browser after reconnection.";
        pendingSave = -1; pendingCommand = -1;
        clearVolume();
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
    // Show the requested volume briefly while the player settles, then reconcile.
    Timer { id: volumeConfirmTimer; interval: 2500; onTriggered: root.targetVolume = -1 }
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
        function status(): string { return JSON.stringify({online: root.online, address: root.address, savedAddress: root.savedAddress, iconMode: root.iconMode, backendPid: backend.processId, panelOpen: root.shell ? root.shell.isPluginOpen("delormous.volumio") : false, state: root.snapshot, error: root.lastError}); }
        function refresh(): void { root.refresh(); }
        function configure(address: string): void { root.saveAddress(address); }
        function action(command: string): void { root.action(command); }
        function volume(value: int): void { root.setVolume(value, true); }
    }
}
