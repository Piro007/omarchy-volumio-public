import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
    name: "PlaybackTiming"
    when: windowShown
    width: 340; height: 240
    Plugin.PlaybackTiming { id: timing; width: 300; online: true }
    function test_format_and_progress() {
        timing.snapshot = {seek: 53057, duration: 809};
        compare(timing.timeText, "0:53 / 13:29");
        verify(timing.progressVisible);
        fuzzyCompare(timing.fraction, 53.057 / 809, 0.00001);
        timing.snapshot = {seek: 3661000, duration: 7200};
        compare(timing.timeText, "1:01:01 / 2:00:00");
        timing.snapshot = {seek: 70000, duration: 60};
        compare(timing.fraction, 1);
    }
    function test_missing_invalid_and_old_backend() {
        for (var snapshot of [{}, {seek: null, duration: null}, {seek: -1, duration: -1}, {seek: NaN, duration: Infinity}]) {
            timing.snapshot = snapshot;
            compare(timing.timeText, "--:-- / --:--");
            verify(!timing.progressVisible);
        }
        timing.snapshot = {seek: 1000, duration: 0};
        compare(timing.timeText, "0:01 / --:--");
        verify(!timing.progressVisible);
    }
    function test_no_interpolation_or_interaction_and_offline_dimming() {
        timing.snapshot = {seek: 1000, duration: 60};
        timing.online = false;
        compare(timing.opacity, 0.5);
        mouseClick(timing, 150, timing.height - 1);
        wait(1100);
        compare(timing.timeText, "0:01 / 1:00");
        verify(!timing.activeFocus);
        timing.online = true;
        compare(timing.opacity, 1);
    }
}
