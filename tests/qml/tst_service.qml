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
        function updateEntryInline(id, settings) {
            // Omarchy's detached snapshot can remain stale after a write.
            if (persisted === settings.address) return false;
            persisted = settings.address;
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
