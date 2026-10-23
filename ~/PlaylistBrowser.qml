pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

FocusScope {
    id: root
    property var service: null
    property color foreground: Commons.Color.foreground
    property string fontFamily: Style.font.family
    signal backRequested()
    signal closeRequested()

    function enter() {
        list.forceActiveFocus();
        if (service) service.browsePlaylists(false);
    }
    function activate(index) {
        if (!service || index < 0 || index >= list.count) return;
        list.currentIndex = index;
        list.forceActiveFocus();
        service.playPlaylist(service.playlists.get(index).name);
    }
    Keys.onEscapePressed: root.closeRequested()

    Row {
        id: header
        width: parent.width
        spacing: Style.space(8)
        Ui.Button {
            id: backButton
            text: "Back"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            onClicked: root.backRequested()
            KeyNavigation.tab: refreshButton
        }
        Text {
            width: Math.max(0, header.width - backButton.width - refreshButton.width - header.spacing * 2)
            anchors.verticalCenter: parent.verticalCenter
            text: "Saved playlists"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
        }
        Ui.Button {
            id: refreshButton
            text: "Refresh"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            enabled: root.service && root.service.ready && !root.service.busy
            onClicked: { root.service.browsePlaylists(true); list.forceActiveFocus(); }
            KeyNavigation.tab: list
        }
    }
    Text {
        id: message
        anchors.top: header.bottom
        anchors.topMargin: Style.space(8)
        width: parent.width
        text: !root.service ? "Service unavailable"
            : root.service.playlistError
            || (root.service.pendingPlaylist >= 0 ? "Starting playlist…"
            : root.service.browsingPlaylists ? "Loading playlists…"
            : !root.service.online ? "Volumio unreachable"
            : root.service.playlistsComplete && list.count === 0 ? "No saved playlists"
            : list.count + " playlists · Select to replace the queue and play")
        color: root.service && (root.service.playlistError || !root.service.online)
            ? Commons.Color.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
    }
    ListView {
        id: list
        anchors.top: message.bottom
        anchors.topMargin: Style.space(12)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        focus: true
        spacing: Style.space(6)
        model: root.service ? root.service.playlists : null
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        keyNavigationWraps: false
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 120
        onCountChanged: if (count > 0 && currentIndex < 0) currentIndex = 0
        KeyNavigation.tab: backButton
        KeyNavigation.backtab: refreshButton
        Keys.onReturnPressed: root.activate(currentIndex)
        Keys.onEnterPressed: root.activate(currentIndex)
        Keys.onSpacePressed: function(event) { event.accepted = true; }
        Controls.ScrollBar.vertical: Controls.ScrollBar {
            policy: Controls.ScrollBar.AsNeeded
            contentItem: Rectangle { implicitWidth: Style.space(3); radius: width / 2; color: root.foreground; opacity: 0.4 }
            background: Item {}
        }
        delegate: Ui.Button {
            id: row
            required property int index
            required property string name
            width: list.width - Style.space(8)
            height: Style.space(48)
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: list.activeFocus && list.currentIndex === index
            selected: root.service && root.service.activatingPlaylist === name
            color: selected ? Style.selectedFillFor(foreground, accent) : "transparent"
            borderSpec: hasCursor ? Border.withWidth(Border.controlSpec("focus", foreground, accent), 1) : Border.none()
            enabled: root.service && root.service.online && root.service.supportsPlaylists && !root.service.busy
            opacity: enabled ? 1 : 0.55
            tooltipText: name
            onClicked: root.activate(index)
            Text {
                anchors.fill: parent
                anchors.margins: Style.space(12)
                text: row.name
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }
}
