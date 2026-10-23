import QtQuick
import QtQuick.Controls as Controls

// Used by the control panel when the screen cannot fit its natural height.
Flickable {
    id: root
    default property alias content: column.data
    property alias spacing: column.spacing
    property color foreground: "white"
    implicitHeight: column.implicitHeight
    contentWidth: width
    contentHeight: column.implicitHeight
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    function reveal(item) {
        if (!item) return;
        var ancestor = item;
        while (ancestor && ancestor !== column) ancestor = ancestor.parent;
        if (!ancestor) return;
        var top = item.mapToItem(column, 0, 0).y;
        var next = contentY;
        if (top < next) next = top;
        else if (top + item.height > next + height) next = top + item.height - height;
        contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), next));
    }
    function revealFocus() { if (root.Window.window) reveal(root.Window.window.activeFocusItem); }
    function scrollBy(amount) { contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), contentY + amount)); }
    onHeightChanged: Qt.callLater(revealFocus)
    onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)))

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() { Qt.callLater(root.revealFocus); }
    }
    flickableData: Column { id: column; width: root.width }
    Controls.ScrollBar.vertical: Controls.ScrollBar {
        policy: Controls.ScrollBar.AsNeeded
        contentItem: Rectangle { implicitWidth: 3; radius: width / 2; color: root.foreground; opacity: 0.4 }
        background: Item {}
    }
}
