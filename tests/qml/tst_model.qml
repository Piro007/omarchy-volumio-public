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
    function test_long_title() {
        verify(Model.barLabel(true, {title: "abcdefghijklmnopqrstuvwxyz0123456789"}).length <= 24);
        compare(Model.barLabel(true, {}), "Volumio");
        verify(Model.safeTooltip({title: "<b>titre</b>\nligne"}).indexOf("<") < 0);
    }
}
