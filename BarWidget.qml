import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

Ui.BarWidget {
    id: root
    moduleName: "delormous.volumio"
    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    readonly property bool opened: popup.opened
    readonly property bool popoutSwitchClosing: popup.popoutSwitchClosing
    readonly property bool online: root.service ? root.service.online : false
    readonly property var snapshot: root.service ? root.service.snapshot : ({})
    readonly property string iconMode: root.service ? root.service.iconMode : "cover"
    readonly property bool playing: root.online && root.snapshot.status === "play"
    readonly property bool signalActive: root.online
        && (root.snapshot.status === "play" || root.snapshot.status === "pause")
    readonly property int iconBarSize: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
    readonly property int coverSize: Math.max(12, root.iconBarSize - Style.space(4))
    readonly property int scopeHeight: Math.max(12, Math.round(root.iconBarSize * 0.64))
    readonly property int scopeWidth: Math.max(24, Math.round(root.scopeHeight * 1.9))
    readonly property int scopeSlot: root.scopeWidth + Style.space(4)
    readonly property int slotWidth: root.vertical ? root.iconBarSize
        : (root.iconMode === "cover" ? root.iconBarSize : root.scopeSlot)
    readonly property int slotHeight: root.vertical
        ? (root.iconMode === "cover" ? root.iconBarSize : root.scopeSlot) : root.iconBarSize
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function open() { popup.open(); }
    function close() { popup.close(); }
    function toggle() { popup.toggle(); }
    function closeForPopoutSwitch() { popup.closeForPopoutSwitch(); }
    property var observedAddress: null
    property var observedIconMode: null
    // Initial settings can be stale in host slots recreated after a rescan.
    // The service initializes from shell.barConfig; only forward later edits.
    function syncSettings() {
        var value = root.setting("address", "http://volumio.local");
        if (observedAddress !== null && observedAddress !== value && root.service)
            root.service.configure(value);
        observedAddress = value;
        var mode = root.setting("barIcon", "cover");
        if (observedIconMode !== null && observedIconMode !== mode && root.service)
            root.service.syncIconMode(mode);
        observedIconMode = mode;
    }
    onSettingsChanged: syncSettings()

    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: ""
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.vertical ? -1 : root.slotWidth
        fixedHeight: root.vertical ? root.slotHeight : -1
        foreground: root.online ? root.bar.barForeground : root.bar.urgent
        tooltipText: root.online ? Model.safeTooltip(root.snapshot) : "Volumio unreachable — click to configure"
        onPressed: function(code) {
            if (code === Qt.LeftButton) root.toggle();
            else if (code === Qt.RightButton && root.service) root.service.toggleIconMode();
        }

        Item {
            id: cover
            anchors.centerIn: parent
            width: root.coverSize
            height: root.coverSize
            visible: root.iconMode === "cover"

            Rectangle {
                id: coverFrame
                anchors.fill: parent
                radius: Math.min(Style.space(3), height / 3)
                color: Style.selectedFillFor(button.foreground, Commons.Color.accent)
                border.width: 1
                border.color: Style.selectedBorderFor(button.foreground, Commons.Color.accent)
                clip: true

                Image {
                    id: artwork
                    anchors.fill: parent
                    anchors.margins: 1
                    source: root.snapshot.albumart || ""
                    sourceSize.width: 64
                    sourceSize.height: 64
                    asynchronous: true
                    cache: true
                    fillMode: Image.PreserveAspectCrop
                    visible: source !== "" && status !== Image.Error
                    opacity: root.online ? 1 : 0.5
                }

                Ui.OpticalGlyph {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    visible: !artwork.visible
                    text: "󰝚"
                    fontFamily: button.fontFamily
                    fontSize: Style.bar.iconFont
                    color: button.foreground
                }
            }
        }

        Oscilloscope {
            id: scope
            anchors.centerIn: parent
            width: root.vertical ? root.scopeHeight : root.scopeWidth
            height: root.vertical ? root.scopeWidth : root.scopeHeight
            visible: root.iconMode === "scope"
            foreground: button.foreground
            running: root.playing
            active: root.signalActive
            cornerRadius: Math.min(Style.space(3), height / 3)
        }
    }

    ControlPanel {
        id: popup
        bar: root.bar
        anchorItem: button
        hostWidget: root
        service: root.service
    }
}
