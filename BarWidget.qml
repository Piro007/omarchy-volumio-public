import QtQuick
import qs.Ui as Ui
import "Model.js" as Model

Ui.BarWidget {
    id: root
    moduleName: "delormous.volumio"
    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    readonly property bool opened: popup.opened
    readonly property bool popoutSwitchClosing: popup.popoutSwitchClosing
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function open() { popup.open(); }
    function close() { popup.close(); }
    function toggle() { popup.toggle(); }
    function closeForPopoutSwitch() { popup.closeForPopoutSwitch(); }
    property var observedAddress: null
    // Initial settings can be stale in host slots recreated after a rescan.
    // The service initializes from shell.barConfig; only forward later edits.
    function syncSettings() {
        var value = root.setting("address", "http://volumio.local");
        if (observedAddress !== null && observedAddress !== value && root.service)
            root.service.configure(value);
        observedAddress = value;
    }
    onSettingsChanged: syncSettings()

    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: (root.service && root.service.online && root.service.snapshot.status === "play" ? "󰎈 " : "󰝚 ")
            + Model.barLabel(root.service ? root.service.online : false, root.service ? root.service.snapshot : {})
        foreground: root.service && root.service.online ? root.bar.barForeground : root.bar.urgent
        tooltipText: root.service && root.service.online ? Model.safeTooltip(root.service.snapshot) : "Volumio unreachable — click to configure"
        onPressed: function(code) { if (code === Qt.LeftButton) root.toggle(); }
    }
    ControlPanel {
        id: popup
        bar: root.bar
        anchorItem: button
        hostWidget: root
        service: root.service
    }
}
