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
        grid.forceActiveFocus();
        if (service) service.browseAlbums(false);
    }
    function activate(index) {
        if (!service || index < 0 || index >= grid.count) return;
        grid.currentIndex = index;
        grid.forceActiveFocus();
        service.playAlbum(service.albums.get(index).uri);
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
            text: "Internal albums"
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
            enabled: root.service && root.service.ready && root.service.pendingAlbum < 0
            onClicked: { root.service.browseAlbums(true); grid.forceActiveFocus(); }
            KeyNavigation.tab: grid
        }
    }
    Text {
        id: message
        anchors.top: header.bottom
        anchors.topMargin: Style.space(8)
        width: parent.width
        text: !root.service ? "Service unavailable"
            : root.service.albumError || root.service.libraryError
            || (root.service.pendingAlbum >= 0 ? "Starting album…"
            : root.service.browsing ? "Loading albums…"
            : !root.service.online ? "Volumio unreachable"
            : root.service.albumsComplete && grid.count === 0 ? "No albums in internal storage"
            : grid.count + " albums · Select a cover to play")
        color: root.service && (root.service.albumError || root.service.libraryError || !root.service.online)
            ? Commons.Color.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
    }
    GridView {
        id: grid
        anchors.top: message.bottom
        anchors.topMargin: Style.space(8)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        focus: true
        model: root.service ? root.service.albums : null
        cellWidth: width / 3
        cellHeight: cellWidth + Style.space(44)
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
        // Space never invokes the control panel's play/pause shortcut here.
        Keys.onSpacePressed: function(event) { event.accepted = true; }
        Controls.ScrollBar.vertical: Controls.ScrollBar {
            policy: Controls.ScrollBar.AsNeeded
            contentItem: Rectangle { implicitWidth: Style.space(3); radius: width / 2; color: root.foreground; opacity: 0.4 }
            background: Item {}
        }
        delegate: Ui.Button {
            id: tile
            required property int index
            required property string uri
            required property string title
            required property string albumart
            width: grid.cellWidth - Style.space(8)
            height: grid.cellHeight - Style.space(8)
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: grid.activeFocus && grid.currentIndex === index
            selected: root.service && root.service.activatingAlbum === uri
            enabled: root.service && root.service.online && root.service.supportsLibrary && !root.service.busy
            opacity: enabled ? 1 : 0.55
            tooltipText: title
            onClicked: root.activate(index)
            Column {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(6)
                Rectangle {
                    width: parent.width
                    height: width
                    color: Style.selectedFillFor(root.foreground, Commons.Color.accent)
                    radius: Style.cornerRadius
                    Image {
                        id: artwork
                        anchors.fill: parent
                        source: tile.albumart
                        sourceSize.width: 256
                        sourceSize.height: 256
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !artwork.visible
                        text: "󰝚"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.displayLarge
                    }
                }
                Text {
                    width: parent.width
                    text: tile.title
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                }
            }
        }
    }
}
