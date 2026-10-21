pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

Ui.Panel {
    id: root
    moduleName: "delormous.volumio"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    property var service: null
    readonly property var snapshot: service ? service.snapshot : ({})
    readonly property bool online: service ? service.online : false
    readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    onOpenedChanged: if (opened) {
        addressField.text = service ? service.address : "http://volumio.local";
        if (service) service.refresh();
    }
    function switchPanel(direction) {
        return bar ? bar.switchPanelFrom(hostWidget || root, direction) : false;
    }
    Ui.KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keys
        contentWidth: panel.fittedContentWidth(Style.space(340))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)
        Ui.PanelKeyCatcher {
            id: keys
            anchors.fill: parent
            blocked: addressField.activeFocus
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction); }
            onActivateRequested: if (root.service) root.service.action(root.snapshot.status === "play" ? "pause" : "play")
            onMoveRequested: function(dx, dy) {
                if (dx !== 0 && root.online && !root.snapshot.disableVolumeControl)
                    root.service.setVolume(root.snapshot.volume + dx, true);
            }
            Column {
                id: content
                width: parent.width
                spacing: Style.space(12)
                Row {
                    width: parent.width
                    spacing: Style.space(12)
                    Rectangle {
                        width: Style.space(80); height: width
                        radius: Style.cornerRadius
                        color: Style.selectedFillFor(root.foreground, Commons.Color.accent)
                        Image {
                            id: cover
                            anchors.fill: parent
                            source: root.snapshot.albumart || ""
                            sourceSize.width: 256; sourceSize.height: 256
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !cover.visible
                            text: "󰝚"; color: root.foreground
                            font.pixelSize: Style.font.displayLarge
                            font.family: root.fontFamily
                        }
                    }
                    Column {
                        width: parent.width - Style.space(92)
                        spacing: Style.space(4)
                        Label { text: root.snapshot.title || "Volumio"; font.bold: true; font.pixelSize: Style.font.subtitle; maximumLineCount: 2; wrapMode: Text.Wrap }
                        Label { text: root.snapshot.artist || "Unknown artist" }
                        Label { text: root.snapshot.album || ""; opacity: 0.65; visible: text !== "" }
                    }
                }
                Label {
                    text: Model.statusLabel(root.online, root.service ? root.service.connecting : true, root.snapshot)
                    color: root.online ? root.foreground : Commons.Color.urgent
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(12)
                    Ui.Button {
                        focusable: true
                        iconText: "󰒮"; foreground: root.foreground
                        tooltipText: "Previous"
                        enabled: root.online && root.service && !root.service.busy
                        onClicked: root.service.action("previous")
                    }
                    Ui.Button {
                        focusable: true
                        iconText: root.snapshot.status === "play" ? "󰏤" : "󰐊"
                        iconSize: Style.font.iconLarge
                        foreground: root.foreground
                        tooltipText: root.snapshot.status === "play" ? "Pause" : "Play"
                        enabled: root.online && root.service && !root.service.busy
                        onClicked: root.service.action(root.snapshot.status === "play" ? "pause" : "play")
                    }
                    Ui.Button {
                        focusable: true
                        iconText: "󰒭"; foreground: root.foreground
                        tooltipText: "Next"
                        enabled: root.online && root.service && !root.service.busy
                        onClicked: root.service.action("next")
                    }
                }
                Column {
                    width: parent.width
                    Label { text: root.snapshot.disableVolumeControl ? "Volume unavailable" : "Volume · " + Math.round(volume.liveValue) + " %" + (root.snapshot.mute ? " · Muted" : "") }
                    Ui.PanelSlider {
                        id: volume
                        width: parent.width
                        bar: root.bar
                        minimum: 0; maximum: 100; step: 1; integer: true
                        value: typeof root.snapshot.volume === "number" ? root.snapshot.volume : 0
                        enabled: root.online && !root.snapshot.disableVolumeControl
                        opacity: enabled ? 1 : 0.4
                        activeFocusOnTab: true
                        onMoved: function(value) { root.service.setVolume(value, false); }
                        onReleased: function(value) { root.service.setVolume(value, true); }
                        Keys.onLeftPressed: if (enabled) root.service.setVolume(Math.max(0, value - 1), true)
                        Keys.onRightPressed: if (enabled) root.service.setVolume(Math.min(100, value + 1), true)
                    }
                }
                Ui.PanelSeparator { foreground: root.foreground }
                Label { text: "PLAYER"; font.pixelSize: Style.font.caption; opacity: 0.65 }
                Ui.TextField {
                    id: addressField
                    width: parent.width
                    foreground: root.foreground
                    placeholderText: "http://volumio.local"
                    selectByMouse: true
                    onAccepted: if (root.service) root.service.saveAddress(text)
                    Keys.onEscapePressed: { focus = false; root.close(); }
                }
                Row {
                    spacing: Style.space(8)
                    Ui.Button {
                        focusable: true; text: "Save"; foreground: root.foreground; enabled: root.service && root.service.ready; onClicked: root.service.saveAddress(addressField.text) }
                    Ui.Button {
                        focusable: true; text: "Refresh"; foreground: root.foreground; onClicked: if (root.service) root.service.refresh() }
                }
                Label {
                    text: root.service ? root.service.lastError : "Service unavailable"
                    visible: text !== ""
                    color: Commons.Color.urgent
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                }
            }
        }
    }
    component Label: Text {
        width: parent.width
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
}
