import QtQuick
import QtTest
import Quickshell.Io
import "../.." as Plugin

TestCase {
    id: test
    name: "VolumioService"
    property var service
    Component { id: serviceComponent; Plugin.Service { autoStart: false } }
    QtObject {
        id: shell
        property var barConfig: ({})
        property string persisted: ""
        property int writes: 0
        property var entry: null
        property string entryJson: ""
        function updateEntryInline(id, settings) {
            // Omarchy's detached snapshot can remain stale after a write.
            var json = JSON.stringify(settings);
            if (entryJson === json) return false;
            entry = settings;
            entryJson = json;
            if (settings.address !== undefined) persisted = String(settings.address);
            writes++;
            return true;
        }
        function isPluginOpen(id) { return false; }
    }
    function init() {
        Harness.requests = [];
        Harness.starts = 0;
        shell.writes = 0;
        shell.persisted = "http://music.local/";
        shell.entry = null;
        shell.entryJson = "";
        shell.barConfig = {layout: {right: [{id: "delormous.volumio", address: shell.persisted}]}};
        service = serviceComponent.createObject(test, {shell: shell});
        verify(service !== null);
    }
    function cleanup() { service.destroy(); wait(0); }
    function deliver(event) { service.receive(JSON.stringify(event)); }
    function online() {
        deliver({type: "ready", protocol: 1});
        deliver({type: "state", state: {status: "pause", volume: 20, disableVolumeControl: false}});
    }
    function test_initial_saved_address_and_idempotent_save() {
        deliver({type: "ready", protocol: 1});
        compare(Harness.requests[0].address, shell.persisted);
        service.saveAddress("http://another.local");
        deliver({type: "configured", id: service.pendingSave, address: "http://another.local/"});
        compare(shell.persisted, "http://another.local/");
        compare(service.savedAddress, shell.persisted);
        service.saveAddress("http://another.local/");
        deliver({type: "configured", id: service.pendingSave, address: "http://another.local/"});
        compare(shell.writes, 1);
        compare(service.lastError, "");
    }
    function test_failure_drops_pending_commands_and_volume() {
        online();
        service.action("play");
        service.setVolume(30, true);
        service.setVolume(40, false);
        service.saveAddress("http://another.local");
        service.failed();
        compare(service.online, false);
        compare(service.busy, false);
        compare(service.pendingSave, -1);
        compare(service.pendingVolume, -1);
        compare(service.desiredVolume, -1);
        var count = Harness.requests.length;
        wait(200);
        compare(Harness.requests.length, count);
        deliver({type: "ready", protocol: 1});
        compare(Harness.requests.length, count + 1);
        compare(Harness.requests[count].op, "configure");
        compare(Harness.requests[count].address, shell.persisted);
    }
    function test_current_config_overrides_stale_facade_after_reload() {
        online();
        service.receiveConfig(JSON.stringify({bar: {layout: {right: [
            {id: "delormous.volumio", address: "http://saved.local/"}
        ]}}}));
        compare(service.savedAddress, "http://saved.local/");
        compare(Harness.requests[Harness.requests.length - 1].address, "http://saved.local/");
        compare(shell.writes, 0);
        service.receiveConfig("invalid");
        compare(service.savedAddress, "http://saved.local/");
        verify(service.lastError.indexOf("Could not read") >= 0);
    }
    function test_icon_mode_persists_with_address() {
        deliver({type: "ready", protocol: 1});
        compare(service.iconMode, "cover");
        service.toggleIconMode();
        compare(service.iconMode, "scope");
        compare(service.savedIconMode, "scope");
        compare(shell.entry.barIcon, "scope");
        compare(shell.entry.address, shell.persisted);
        service.saveAddress("http://another.local");
        deliver({type: "configured", id: service.pendingSave, address: "http://another.local/"});
        compare(shell.entry.barIcon, "scope");
        compare(shell.entry.address, "http://another.local/");
        service.toggleIconMode();
        compare(service.iconMode, "cover");
        compare(shell.entry.barIcon, "cover");
        compare(shell.entry.address, "http://another.local/");
        compare(shell.writes, 3);
    }
    function test_saved_icon_mode_restored_from_config() {
        service.receiveConfig(JSON.stringify({bar: {layout: {right: [
            {id: "delormous.volumio", address: "http://saved.local/", barIcon: "scope"}
        ]}}}));
        compare(service.iconMode, "scope");
        compare(service.savedIconMode, "scope");
        compare(shell.writes, 0);
        service.receiveConfig(JSON.stringify({bar: {layout: {right: [
            {id: "delormous.volumio", address: "http://saved.local/"}
        ]}}}));
        compare(service.iconMode, "cover");
    }
    function test_injected_icon_mode_is_saved_state() {
        service.destroy();
        wait(0);
        shell.barConfig = {layout: {right: [
            {id: "delormous.volumio", address: shell.persisted, barIcon: "scope"}
        ]}};
        service = serviceComponent.createObject(test, {shell: shell});
        verify(service !== null);
        compare(service.iconMode, "scope");
        compare(service.savedIconMode, "scope");
        service.toggleIconMode();
        compare(service.iconMode, "cover");
        compare(shell.entry.barIcon, "cover");
    }
    function test_external_icon_mode_is_then_toggleable() {
        service.syncIconMode("scope");
        compare(service.iconMode, "scope");
        compare(service.savedIconMode, "scope");
        compare(shell.writes, 0);
        service.toggleIconMode();
        compare(service.iconMode, "cover");
        compare(shell.entry.barIcon, "cover");
        compare(shell.writes, 1);
    }
    function test_icon_mode_toggle_is_idempotent() {
        service.setIconMode("scope");
        compare(service.iconMode, "scope");
        compare(shell.writes, 1);
        service.setIconMode("scope");
        compare(shell.writes, 1);
        service.setIconMode("bogus");
        compare(service.iconMode, "cover");
        compare(shell.writes, 2);
    }
    function test_volume_coalescing_and_disabled_control() {
        online();
        service.setVolume(21, true);
        var first = service.pendingVolume;
        service.setVolume(22, true);
        service.setVolume(23, true);
        compare(Harness.requests.length, 2); // configure + first volume
        deliver({type: "result", id: first, ok: true});
        compare(Harness.requests.length, 3);
        compare(Harness.requests[2].volume, 23);
        deliver({type: "state", state: {status: "pause", disableVolumeControl: true}});
        service.setVolume(50, true);
        compare(Harness.requests.length, 3);
    }
    function test_offline_blocks_actions_and_preserves_metadata() {
        online();
        deliver({type: "connection", online: false, connecting: false});
        service.action("next");
        service.setVolume(40, true);
        compare(Harness.requests.length, 1);
        compare(service.snapshot.status, "pause");
    }
    function libraryOnline() {
        deliver({type: "ready", protocol: 1, features: ["albums"]});
        deliver({type: "state", state: {status: "pause", volume: 20, disableVolumeControl: false}});
    }
    function test_completed_album_scan_is_cached_until_refresh() {
        libraryOnline();
        service.browseAlbums(false);
        var id = service.browseId;
        deliver({type: "albums", id: id, items: [{uri: "albums://Artist/Album", title: "Album"}], done: false});
        compare(service.albums.count, 1);
        verify(service.browsing);
        deliver({type: "albums", id: id, items: [], done: true});
        verify(service.albumsComplete);
        verify(!service.browsing);
        var count = Harness.requests.length;
        service.cancelBrowse();
        service.browseAlbums(false);
        compare(Harness.requests.length, count);
        compare(service.albums.count, 1);
        service.browseAlbums(true);
        compare(Harness.requests.length, count + 1);
        compare(Harness.requests[count].op, "browse_albums");
        compare(service.albums.count, 0);
        verify(!service.albumsComplete);
        verify(service.browseId !== id);
    }
    function test_cancelled_album_scan_ignores_stale_events() {
        libraryOnline();
        service.browseAlbums(false);
        var oldId = service.browseId;
        service.cancelBrowse();
        compare(Harness.requests[Harness.requests.length - 1].op, "cancel_browse");
        deliver({type: "albums", id: oldId, items: [{uri: "albums://Old/Album", title: "Old"}], done: true});
        compare(service.albums.count, 0);
        verify(!service.albumsComplete);
        service.browseAlbums(false);
        var newId = service.browseId;
        deliver({type: "library_error", id: oldId, error: "Stale failure"});
        compare(service.libraryError, "");
        compare(service.browseId, newId);
        deliver({type: "albums", id: newId, items: [{uri: "albums://New/Album", title: "New"}], done: true});
        compare(service.albums.count, 1);
        compare(service.albums.get(0).title, "New");
        verify(service.albumsComplete);
    }
    function test_album_activation_blocks_duplicates_and_does_not_retry_failure() {
        libraryOnline();
        service.playAlbum("albums://Artist/Album");
        var id = service.pendingAlbum;
        verify(service.busy);
        compare(service.activatingAlbum, "albums://Artist/Album");
        var count = Harness.requests.length;
        service.playAlbum("albums://Other/Album");
        compare(Harness.requests.length, count);
        deliver({type: "result", id: id, ok: false, error: "Queue may have changed"});
        verify(!service.busy);
        compare(service.activatingAlbum, "");
        compare(service.albumError, "Queue may have changed");
        verify(service.online);
        compare(Harness.requests.length, count + 1);
        compare(Harness.requests[count].op, "refresh");
        deliver({type: "state", state: {status: "play", volume: 20}});
        compare(Harness.requests.length, count + 1);
    }
    function playlistsOnline() {
        deliver({type: "ready", protocol: 1, features: ["albums", "playlists"]});
        deliver({type: "state", state: {status: "pause", volume: 20, disableVolumeControl: false}});
    }
    function test_playlist_cache_refresh_and_cancellation() {
        playlistsOnline();
        service.browsePlaylists(false);
        var id = service.playlistBrowseId;
        verify(service.browsingPlaylists);
        deliver({type: "playlists", id: id, items: [{name: "Été & Jazz"}], done: true});
        compare(service.playlists.count, 1);
        compare(service.playlists.get(0).name, "Été & Jazz");
        verify(service.playlistsComplete);
        var count = Harness.requests.length;
        service.browsePlaylists(false);
        compare(Harness.requests.length, count);
        service.browsePlaylists(true);
        compare(service.playlists.count, 0);
        id = service.playlistBrowseId;
        service.cancelBrowse();
        compare(Harness.requests[Harness.requests.length - 1].op, "cancel_browse");
        service.browsePlaylists(false);
        var newId = service.playlistBrowseId;
        deliver({type: "playlists", id: id, items: [{name: "Stale"}], done: true});
        compare(service.playlists.count, 0);
        compare(service.playlistBrowseId, newId);
        deliver({type: "playlists", id: newId, items: [], done: true});
        verify(service.playlistsComplete);
        compare(service.playlists.count, 0);
        count = Harness.requests.length;
        service.browsePlaylists(false);
        compare(Harness.requests.length, count);
        deliver({type: "configured", address: "http://new.local/"});
        verify(!service.playlistsComplete);
        compare(service.playlists.count, 0);
    }
    function test_playlist_errors_and_backend_compatibility() {
        online();
        service.browsePlaylists(false);
        verify(service.playlistError.indexOf("updated backend") >= 0);
        compare(Harness.requests.length, 1);
        playlistsOnline();
        service.browsePlaylists(false);
        deliver({type: "library_error", id: service.playlistBrowseId, error: "Could not list playlists"});
        verify(!service.browsingPlaylists);
        compare(service.playlistError, "Could not list playlists");
        verify(service.online);
        service.action("play");
        compare(Harness.requests[Harness.requests.length - 1].op, "play");
    }
    function test_playlist_activation_blocks_duplicates_and_cleans_up_without_replay() {
        playlistsOnline();
        service.playPlaylist("Été & Jazz");
        var id = service.pendingPlaylist;
        verify(service.busy);
        compare(service.activatingPlaylist, "Été & Jazz");
        compare(Harness.requests[Harness.requests.length - 1].name, "Été & Jazz");
        var count = Harness.requests.length;
        service.playPlaylist("Other");
        service.playAlbum("albums://Artist/Album");
        service.action("next");
        compare(Harness.requests.length, count);
        deliver({type: "result", id: id, ok: false, error: "Queue may have changed"});
        verify(!service.busy);
        verify(service.online);
        compare(service.activatingPlaylist, "");
        compare(service.playlistError, "Queue may have changed");
        compare(Harness.requests.length, count + 1);
        compare(Harness.requests[count].op, "refresh");
        service.playPlaylist("Other");
        service.failed();
        compare(service.pendingPlaylist, -1);
        compare(service.activatingPlaylist, "");
        verify(!service.supportsPlaylists);
        count = Harness.requests.length;
        playlistsOnline();
        compare(Harness.requests.length, count + 1);
        compare(Harness.requests[count].op, "configure");
    }
    function test_missing_backend_reports_failure() {
        service.startBackend();
        compare(Harness.starts, 1);
        service.startBackend();
        compare(Harness.starts, 1);
        tryVerify(function() { return service.lastError.indexOf("Backend unavailable") >= 0; }, 6000);
        compare(service.online, false);
        compare(Harness.process.running, false);
    }
    function test_destroy_stops_process() {
        service.startBackend();
        var process = Harness.process;
        verify(process.running);
        service.destroy();
        wait(0);
        // The process is owned by the service, not a detached global daemon.
        compare(Harness.process, null);
        service = serviceComponent.createObject(test);
    }
    function test_process_exit_schedules_one_restart() {
        service.autoStart = true;
        service.startBackend();
        online();
        Harness.process.running = false;
        Harness.process.exited(1, 0);
        compare(service.ready, false);
        tryCompare(Harness, "starts", 2, 4000);
        deliver({type: "ready", protocol: 1});
        wait(100);
        compare(Harness.starts, 2);
        compare(Harness.requests[Harness.requests.length - 1].op, "configure");
    }
}
