import QtQuick
import QtTest
import "../../Model.js" as Model

TestCase {
    name: "VolumioModel"
    function test_address_from_persisted_bar() {
        compare(Model.addressFromBar({}), "http://volumio.local");
        compare(Model.addressFromBar({layout: {right: [{id: "other", address: "wrong"},
            {id: "delormous.volumio", address: "http://127.0.0.1:9/"}]}}), "http://127.0.0.1:9/");
        compare(Model.addressFromBar({layout: {left: [{id: "delormous.volumio", address: "http://music.local"}]}}), "http://music.local");
    }
    function test_address_in_each_supported_section() {
        var sections = ["left", "centerBegin", "center", "centerEnd", "tray", "right"];
        for (var i = 0; i < sections.length; ++i) {
            var layout = {};
            layout[sections[i]] = [{id: "delormous.volumio", address: "http://music.local/"}];
            compare(Model.addressFromBar({layout: layout}), "http://music.local/");
        }
    }
    function test_status() {
        compare(Model.statusLabel(false, false, {}), "Volumio unreachable");
        compare(Model.statusLabel(false, true, {}), "Connecting…");
        compare(Model.statusLabel(true, false, {status: "pause"}), "Paused");
    }
    function test_tooltip() {
        verify(Model.safeTooltip({title: "<b>titre</b>\nligne"}).indexOf("<") < 0);
    }
    function test_icon_mode_from_persisted_bar() {
        compare(Model.iconModeFromBar({}), "cover");
        compare(Model.iconModeFromBar({layout: {right: [
            {id: "delormous.volumio", barIcon: "scope"}]}}), "scope");
        compare(Model.iconModeFromBar({layout: {left: [
            {id: "delormous.volumio", barIcon: "bogus"}]}}), "cover");
        compare(Model.iconModeFromBar({layout: {center: [
            {id: "other", barIcon: "scope"}]}}), "cover");
    }
    function test_waveforms() {
        compare(Model.waveValue("sine", 0), 0);
        fuzzyCompare(Model.waveValue("sine", Math.PI / 2), 1, 1e-9);
        compare(Model.waveValue("square", 0.1), 1);
        compare(Model.waveValue("square", Math.PI + 0.1), -1);
        compare(Model.waveValue("saw", 0), -1);
        compare(Model.waveValue("triangle", 0), 0);
        fuzzyCompare(Model.waveValue("triangle", Math.PI / 2), 1, 1e-9);
        compare(Model.blendWave("sine", "square", 0.3, 0), Model.waveValue("sine", 0.3));
        compare(Model.blendWave("sine", "square", 0.3, 1), Model.waveValue("square", 0.3));
        compare(Model.smoothstep(0), 0);
        compare(Model.smoothstep(1), 1);
        verify(Model.smoothstep(0.5) > 0.49 && Model.smoothstep(0.5) < 0.51);
    }
}
