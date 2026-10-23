import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
    name: "ControlViewport"
    when: windowShown
    width: 340; height: 240
    Plugin.ControlViewport {
        id: viewport
        width: 300; height: 150
        spacing: 12
        Rectangle { id: top; width: parent.width; height: 80 }
        Rectangle { width: parent.width; height: 260 }
        TextInput { id: field; width: parent.width; height: 40; text: "Player address" }
    }
    function test_short_screen_scroll_and_focus() {
        viewport.height = 150;
        viewport.contentY = 0;
        verify(viewport.contentHeight > viewport.height);
        viewport.scrollBy(10000);
        compare(viewport.contentY, viewport.contentHeight - viewport.height);
        viewport.scrollBy(-10000);
        compare(viewport.contentY, 0);
        field.forceActiveFocus();
        tryVerify(function() { return viewport.contentY > 0; });
        verify(field.mapToItem(viewport, 0, field.height).y <= viewport.height);
        viewport.reveal(top);
        compare(viewport.contentY, 0);
        viewport.height = 600;
        viewport.scrollBy(100);
        compare(viewport.contentY, 0);
    }
}
