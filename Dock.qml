import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "adb.audadockbar"
  property var state: ({running:false, docked:true})
  readonly property var audaciousPlayer: {
    var players = Mpris.players ? Mpris.players.values : []
    for (var player of players)
      if (player.dbusName === "org.mpris.MediaPlayer2.audacious") return player
    return null
  }
  // Observe the existing native MPRIS service; never launch audio at login.
  function attachRunningPlayer() {
    if (!audaciousPlayer || bridge.running) return
    root.state = Object.assign({}, root.state, {
      running:true,
      status:audaciousPlayer.isPlaying ? "playing" : "paused"
    })
    pendingCommands = [JSON.stringify({action:"expanded", value:opened}) + "\n"]
    bridge.running = true
  }
  Component.onCompleted: Qt.callLater(root.attachRunningPlayer)
  onAudaciousPlayerChanged: Qt.callLater(root.attachRunningPlayer)
  Timer {
    id:bridgeRecovery
    interval:2000
    onTriggered:root.attachRunningPlayer()
  }
  property bool opened: false
  property bool eqOpen: false
  property bool playlistOpen: false
  property bool fileOpen: false
  property bool urlOpen: false
  property bool listsOpen: false
  property bool presetsOpen: false
  property bool savePresetOpen: false
  property bool newListOpen: false
  property bool editOrder: false
  property bool movePending: false
  property bool fullListNames: false
  property var renameListTarget: null
  property string renameUri: ""
  property bool popoutSwitchClosing: false
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property bool remaining: state.remaining !== false
  readonly property string trackInfo: state.displayTitle || (audaciousPlayer ? audaciousPlayer.trackTitle || audaciousPlayer.identity : "No playback")
  readonly property string barTime: state.stream ? (state.streamState || "disc")
    : (state.duration > 0 ? (remaining ? "−" : "") + stamp(remaining ? Math.max(0,state.duration - (state.time || 0)) : state.time) : "—")
  readonly property bool docked: state.docked !== false
  readonly property bool popupAlignRight: {
    var layout = bar ? bar.layoutConfig : null
    if (layout) {
      for (var section of ["left", "right"]) {
        for (var entry of (layout[section] || []))
          if ((typeof entry === "string" ? entry : entry.id) === moduleName) return section === "right"
      }
    }
    // In the center group, widgets before the central clock grow to the left
    // and are therefore attached by their right edge (and vice versa).
    barPositionWatcher.transform
    var window = root.QsWindow.window
    if (!window || !window.screen) return true
    var point = root.mapToItem(window.contentItem, root.width / 2, 0)
    return point.x <= window.screen.width / 2
  }
  TransformWatcher { id:barPositionWatcher; a:root.QsWindow.window ? root.QsWindow.window.contentItem : null; b:root }
  readonly property real uiScale: state.doubleSize ? 2 : 1
  readonly property real panelHeight: eqOpen || playlistOpen ? 230 : coverImage.status === Image.Ready ? 250 : mainTitle.height + playbackRow.height + volumeControls.height + navigationButtons.height + (seekBar.visible ? seekBar.height : 0) + (playerError.visible ? playerError.height : 0) + playerColumn.spacing * (3 + (seekBar.visible ? 1 : 0) + (playerError.visible ? 1 : 0))
  readonly property real fittedPanelHeight: Math.max(0,popup.contentHeight-popup.verticalContentInset) / uiScale
  visible: docked
  onStateChanged: { movePending = false; if (!docked) close() }
  implicitWidth: compact.implicitWidth + 12
  implicitHeight: barSize

  FileView {
    path: Quickshell.env("HOME") + "/.config/audacious/adb.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      if (!bridge.running) {
        try { root.state = Object.assign({}, JSON.parse(text()), {running:false}) }
        catch(e) { console.warn("Audacious dock preferences:", e) }
      }
    }
  }

  property var pendingCommands: []
  property bool bridgeReady: false
  function send(action, value, band) {
    // Closing an inactive panel must never start the player.
    if (!bridge.running && action === "expanded" && !value) return
    var line = JSON.stringify({action:action, value:value, band:band}) + "\n"
    if (bridgeReady) {
      bridge.write(line)
    } else {
      if (!bridge.running) {
        pendingCommands = [JSON.stringify({action:"dock", value:true}) + "\n", line]
        bridge.running = true
      } else {
        pendingCommands = pendingCommands.concat([line])
      }
    }
  }
  function open() {
    if (!docked) { send("dock", true); }
    send("start"); opened = true
  }
  function close() { editOrder = false; opened = false; fileOpen = false; urlOpen = false; listsOpen = false; newListOpen = false; renameListTarget = null; presetsOpen = false; savePresetOpen = false }
  function saveListName() {
    var title = playlistRenameText.text.trim()
    if (!renameListTarget || title === "") { playlistRenameText.forceActiveFocus(); return }
    send("rename-list", {index:renameListTarget.index, name:renameListTarget.name, title:title})
    renameListTarget = null
  }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  function auxiliary(which) {
    if (which === "eq") {
      eqOpen = !eqOpen
    } else {
      playlistOpen = !playlistOpen
    }
  }
  function moveEntry(from, to) {
    var entries = state.songEntries || []
    if (movePending || to < 0 || to >= entries.length || from === to) return
    movePending = true
    send("move-entry", {playlist:state.playlistIndex, name:state.playlistName,
      uris:entries.map(function(entry) { return entry.uri }), from:from, to:to})
  }
  function stamp(ms) {
    var s = Math.max(0, Math.floor((ms || 0)/1000))
    return Math.floor(s/60) + ":" + (s%60 < 10 ? "0" : "") + s%60
  }
  onOpenedChanged: send("expanded", opened)
  Process {
    id: bridge
    command: ["/usr/bin/python", Quickshell.env("HOME") + "/.local/share/adb/bridge.py"]
    running: false
    stdinEnabled: true
    onStarted: {
      root.bridgeReady = true
      for (var line of root.pendingCommands) bridge.write(line)
      root.pendingCommands = []
    }
    onExited: {
      root.bridgeReady = false
      root.pendingCommands = []
      root.state = Object.assign({}, root.state, {running:!!root.audaciousPlayer})
      if (root.audaciousPlayer) bridgeRecovery.restart()
      else root.close()
    }
    stdout: SplitParser {
      onRead: function(line) {
        try { root.state = JSON.parse(line) } catch(e) { console.warn("Audacious bridge:", e) }
      }
    }
  }
  IpcHandler {
    target: "adb.audadockbar"
    function launch(args: string): void { root.open(); root.send("launch-files", JSON.parse(args)) }
    function dock(value: bool): void { root.send("dock", value); if (value) { root.state = Object.assign({}, root.state, {docked:true}); root.open() } else { root.state = Object.assign({}, root.state, {docked:false}); root.close() } }
    function doubleSize(value: bool): void { root.send("double-size", value) }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function equalizer(): void { root.open(); root.auxiliary("eq") }
    function playlist(): void { root.open(); root.auxiliary("playlist") }
    function lists(): void { root.open(); root.playlistOpen = true; root.listsOpen = true; root.send("list-playlists") }
    function presets(): void { root.open(); root.eqOpen = true; root.presetsOpen = true }
    function editPlaylist(value: bool): void { root.open(); root.playlistOpen = true; root.editOrder = value }
    function toggleTime(): void { root.send("remaining", !root.remaining) }
    function menu(): void { root.open(); root.fileOpen = true;  }
    function inspect(): string { return JSON.stringify({opened:root.opened, bridgeRunning:bridge.running, playerDetected:!!root.audaciousPlayer, equalizer:root.eqOpen, playlist:root.playlistOpen, docked:root.docked, visible:root.visible, doubleSize:root.state.doubleSize === true, width:popup.contentWidth, height:popup.contentHeight, panelHeights:[playerColumn.height,eqColumn.height,playlistColumn.height], coverHeight:coverArea.height, mainOrder:[mainTitle.y,playbackRow.y,seekBar.y,volumeControls.y,coverArea.y,navigationButtons.y], seekVisible:seekBar.visible, seekValue:seekBar.value, timeWidth:trackTime.width, coverStatus:coverImage.status, dropdownWidth:listsDropdown.width, playlistWidth:playlistColumn.width, fullNames:root.fullListNames, editOrder:root.editOrder, presetWidth:presetDropdown.width, barPositions:[compactControls.x,compactTitle.x,compactTime.x], popupAlignRight:root.popupAlignRight, popupOrigin:popup.cardOrigin, titleWidth:compactTitle.width, equalizerOpacity:eqColumn.opacity, timeLabel:root.barTime, trackInfo:root.trackInfo, menu:root.fileOpen, state:root.state}) }
  }
  Row {
    id: compact
    anchors.centerIn: parent
    spacing: 3
    layoutDirection: Qt.RightToLeft
    Row {
      id: compactControls
      visible:root.state.running === true
      anchors.verticalCenter:parent.verticalCenter
      spacing:3
      Button { iconText:"󰒮"; foreground:root.fg; verticalPadding:0; horizontalPadding:3; onClicked:root.send("prev") }
      Button { iconText:root.state.status === "playing" ? "󰏤" : "󰐊"; foreground:root.fg; verticalPadding:0; horizontalPadding:3; onClicked:root.send("play") }
      Button { iconText:"󰒭"; foreground:root.fg; verticalPadding:0; horizontalPadding:3; onClicked:root.send("next") }
    }
    Rectangle {
      id:compactTitle
      width:Math.min(300, songLabel.implicitWidth)+8
      height:root.barSize
      radius:Style.cornerRadius
      color:titleMouse.containsMouse ? Style.hoverFillFor(root.fg,Color.accent) : "transparent"
      Text {
        id:songLabel
        anchors.verticalCenter:parent.verticalCenter
        x:4
        width:parent.width-8
        anchors.verticalCenterOffset:titleMouse.containsMouse && !titleMouse.pressed ? -1 : 0
        text:root.state.running === true ? root.trackInfo : "Audacious"
        textFormat:Text.PlainText
        color:root.fg
        font.family:root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize:Style.font.body
        elide:Text.ElideRight
      }
      MouseArea { id:titleMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:root.toggle() }
    }
    Item {
      id:compactTime
      visible:root.state.running === true
      width:64
      height:root.barSize
      Text {
        anchors.centerIn:parent
        text:root.barTime
        color:root.fg
        textFormat:Text.PlainText
        font.family:root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize:Style.font.body
      }
      MouseArea { anchors.fill:parent; onClicked:root.send("remaining", !root.remaining) }
    }
  }
  Item {
    id:popupAnchor
    width:popup.contentWidth
    height:root.barSize
    x:root.popupAlignRight
      ? compact.x + (root.state.running === true ? compactControls.x + compactControls.width : compactTitle.x + compactTitle.width) - width
      : compact.x + compactTitle.x
  }
  KeyboardPanel {
    id: popup
    anchorItem: popupAnchor
    owner: root
    bar: root.bar
    open: root.opened
    padding: 8
    contentWidth: popup.fittedContentWidth((230 + (root.eqOpen ? 258 : 0) + (root.playlistOpen ? 258 : 0)) * root.uiScale + padding*2 + Border.left(borderSpec) + Border.right(borderSpec))
    contentHeight: popup.fittedContentHeight(root.panelHeight * root.uiScale)
    Row {
      id: panelRow
      scale: root.uiScale
      transformOrigin: Item.TopLeft
      width: (popup.contentWidth-popup.padding*2-Border.left(popup.borderSpec)-Border.right(popup.borderSpec)) / root.uiScale
      height: root.fittedPanelHeight
      spacing: 6
      Column {
        id: playerColumn
        width: 230
        height: root.fittedPanelHeight
        spacing: 4
        Text { id:mainTitle; width:parent.width; text:root.state.running ? root.trackInfo : "Player stopped"; color:root.fg; wrapMode:Text.NoWrap; maximumLineCount:1; elide:Text.ElideRight; font.pixelSize:12; textFormat:Text.PlainText }
        Item {
          id:playbackRow
          width:parent.width
          height:Math.max(playbackButtons.implicitHeight,trackTime.implicitHeight)
          Row {
            id:playbackButtons
            anchors.verticalCenter:parent.verticalCenter
            spacing:2
            Button { iconText:"󰒮"; horizontalPadding:3; verticalPadding:2; foreground:root.fg; onClicked:root.send("prev") }
            Button { iconText:root.state.status === "playing" ? "󰏤" : "󰐊"; horizontalPadding:3; verticalPadding:2; foreground:root.fg; onClicked:root.send("play") }
            Button { iconText:"󰓛"; horizontalPadding:3; verticalPadding:2; foreground:root.fg; onClicked:root.send("stop") }
            Button { iconText:"󰒭"; horizontalPadding:3; verticalPadding:2; foreground:root.fg; onClicked:root.send("next") }
            Button { iconText:"󰒟"; horizontalPadding:3; verticalPadding:2; selected:root.state.shuffle === true; foreground:root.fg; onClicked:root.send("shuffle") }
            Button { iconText:"󰑖"; horizontalPadding:3; verticalPadding:2; selected:root.state.repeat === true; foreground:root.fg; onClicked:root.send("repeat") }
          }
          Text {
            id:trackTime
            anchors.left:playbackButtons.right; anchors.leftMargin:4
            anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter
            horizontalAlignment:Text.AlignRight
            text:root.state.stream ? root.barTime + " · " + root.stamp(root.state.time) : root.stamp(root.state.time) + " / " + (root.state.duration > 0 ? root.stamp(root.state.duration) : "—")
            color:root.fg; opacity:.7; font.pixelSize:10; textFormat:Text.PlainText; elide:Text.ElideRight
          }
        }
        Controls.Slider {
          id:seekBar
          visible:root.state.duration > 0 || root.state.stream === true
          width:parent.width; height:20
          from:0; to:Math.max(1,root.state.duration || 0)
          enabled:root.state.stream !== true && root.state.duration > 0
          value:root.state.stream === true ? 0 : root.state.time || 0
          onMoved:root.send("seek",value)
          background:Rectangle {
            x:seekBar.leftPadding; y:seekBar.topPadding+(seekBar.availableHeight-height)/2
            width:seekBar.availableWidth; height:4; radius:2
            color:root.state.stream === true ? "#1976d2" : "#444444"
            Rectangle { width:parent.width*seekBar.visualPosition; height:parent.height; radius:parent.radius; color:"#1976d2"; visible:root.state.stream !== true }
          }
          handle:Rectangle {
            x:seekBar.leftPadding+seekBar.visualPosition*(seekBar.availableWidth-width)
            y:seekBar.topPadding+(seekBar.availableHeight-height)/2
            width:12; height:12; radius:2
            color:seekBar.pressed ? "#777777" : "#555555"; border.color:"#888888"; border.width:1
          }
        }
        Row {
          id:volumeControls
          spacing:3
          Text { text:"Vol."; color:root.fg; font.pixelSize:11; width:26; anchors.verticalCenter:parent.verticalCenter }
          Controls.Slider { width:158; height:20; from:0; to:100; value:root.state.volume || 0; onMoved:root.send("volume",value) }
          Text { text:Math.round(root.state.volume || 0)+"%"; color:root.fg; font.pixelSize:11; anchors.verticalCenter:parent.verticalCenter }
        }
        Item {
          id:coverArea
          visible:root.eqOpen || root.playlistOpen || coverImage.status === Image.Ready
          width:parent.width
          height:Math.max(0, root.fittedPanelHeight-mainTitle.height-playbackRow.height-volumeControls.height-navigationButtons.height-(seekBar.visible ? seekBar.height : 0)-(playerError.visible ? playerError.height : 0)-playerColumn.spacing*(4+(seekBar.visible ? 1 : 0)+(playerError.visible ? 1 : 0)))
          Image {
            id:coverImage
            anchors.fill:parent
            source:root.opened ? (root.state.artUrl || "") : ""
            sourceSize.width:512; sourceSize.height:512
            fillMode:Image.PreserveAspectFit
            asynchronous:true
            cache:false
            visible:status === Image.Ready
          }
        }
        Text { id:playerError; visible:text !== ""; width:parent.width; text:root.state.error || ""; color:Color.accent; wrapMode:Text.Wrap; maximumLineCount:2; elide:Text.ElideRight; font.pixelSize:11; textFormat:Text.PlainText }
        Row {
          id:navigationButtons
          spacing:2
          Button { id:menuButton; text:"Menu"; fontSize:12; horizontalPadding:5; verticalPadding:3; foreground:root.fg; selected:root.fileOpen; onClicked:root.fileOpen=!root.fileOpen; onHovered:function(hovered) { if (hovered) root.fileOpen=true } }
          Button { text:"Equalizer"; fontSize:12; horizontalPadding:5; verticalPadding:3; foreground:root.fg; selected:root.eqOpen; onClicked:root.auxiliary("eq") }
          Button { text:"Playlist"; fontSize:12; horizontalPadding:5; verticalPadding:3; foreground:root.fg; selected:root.playlistOpen; onClicked:root.auxiliary("playlist") }
        }
        Controls.Menu {
          id: mainMenu
          parent: menuButton
          y: menuButton.height
          width:200
          scale:root.uiScale
          font.pixelSize:12
          background:Rectangle { color:Color.popups.background; border.color:Color.accent; radius:Style.cornerRadius }
          visible:root.opened && root.fileOpen
          onClosed:root.fileOpen=false
          Controls.MenuItem { text:"Open Files …"; onTriggered:{root.send("openfiles"); root.close()} }
          Controls.MenuItem { text:"Open Folder …"; onTriggered:{root.send("openfolder"); root.close()} }
          Controls.MenuItem { text:"Open URL …"; onTriggered:{root.urlOpen=true; streamUrl.forceActiveFocus()} }
          Controls.MenuItem { text:"Search Library"; onTriggered:{root.send("library"); root.close()} }
          Controls.MenuSeparator {}
          Controls.Menu {
            title:"Playback"; width:215; scale:root.uiScale; font.pixelSize:12
            background:Rectangle { color:Color.popups.background; border.color:Color.accent; radius:Style.cornerRadius }
            Controls.MenuItem { text:"Play"; onTriggered:root.send("playonly") }
            Controls.MenuItem { text:"Pause"; onTriggered:root.send("pause") }
            Controls.MenuItem { text:"Stop"; onTriggered:root.send("stop") }
            Controls.MenuItem { text:"Previous"; onTriggered:root.send("prev") }
            Controls.MenuItem { text:"Next"; onTriggered:root.send("next") }
            Controls.MenuItem { text:"Previous Album"; onTriggered:root.send("prevalbum") }
            Controls.MenuItem { text:"Next Album"; onTriggered:root.send("nextalbum") }
            Controls.MenuSeparator {}
            Controls.MenuItem { text:"Repeat"; checkable:true; checked:root.state.repeat === true; onTriggered:root.send("repeat") }
            Controls.MenuItem { text:"Shuffle"; checkable:true; checked:root.state.shuffle === true; onTriggered:root.send("shuffle") }
            Controls.MenuItem { text:"No Playlist Advance"; checkable:true; checked:root.state.advance === false; onTriggered:root.send("advance") }
            Controls.MenuItem { text:"Stop After This Song"; checkable:true; checked:root.state.stopafter === true; onTriggered:root.send("stopafter") }
            Controls.MenuItem { text:"Jump to Song …"; onTriggered:{root.send("jumpdialog"); root.close()} }
          }
          Controls.Menu {
            title:"Output"; width:200; scale:root.uiScale; font.pixelSize:12
            background:Rectangle { color:Color.popups.background; border.color:Color.accent; radius:Style.cornerRadius }
            Controls.MenuItem { text:"Volume Up"; onTriggered:root.send("volumeup") }
            Controls.MenuItem { text:"Volume Down"; onTriggered:root.send("volumedown") }
            Controls.MenuItem { text:"Equalizer"; onTriggered:root.auxiliary("eq") }
            Controls.MenuItem { text:"Effects …"; onTriggered:{root.send("settings"); root.close()} }
            Controls.MenuItem { text:"Record Stream"; checkable:true; checked:root.state.recording === true; onTriggered:root.send("record") }
            Controls.MenuItem { text:"Audio Settings …"; onTriggered:{root.send("settings"); root.close()} }
          }
          Controls.Menu {
            title:"View"; width:200; scale:root.uiScale; font.pixelSize:12
            background:Rectangle { color:Color.popups.background; border.color:Color.accent; radius:Style.cornerRadius }
            Controls.MenuItem { text:"Dock mode"; checkable:true; checked:root.docked; onTriggered:{root.send("dock",!root.docked); root.close()} }
            Controls.MenuItem { text:"Show Equalizer"; checkable:true; checked:root.eqOpen; onTriggered:root.auxiliary("eq") }
            Controls.MenuItem { text:"Show Playlist"; checkable:true; checked:root.playlistOpen; onTriggered:root.auxiliary("playlist") }
            Controls.MenuItem { text:"Remaining time"; checkable:true; checked:root.remaining; onTriggered:root.send("remaining",!root.remaining) }
            Controls.MenuItem { text:"Double size"; checkable:true; checked:root.state.doubleSize === true; onTriggered:root.send("double-size",!root.state.doubleSize) }
          }
          Controls.MenuSeparator {}
          Controls.MenuItem { text:"About …"; onTriggered:{root.send("about"); root.close()} }
          Controls.MenuItem { text:"Settings …"; onTriggered:{root.send("settings"); root.close()} }
          Controls.MenuItem { text:"Quit"; onTriggered:{root.send("quit"); root.close()} }
        }
        Controls.Popup {
          parent:menuButton
          x:-140; y:parent.height+4; width:265; padding:8; scale:root.uiScale
          visible:root.opened && root.urlOpen; focus:true
          closePolicy:Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
          onClosed:root.urlOpen=false
          background:Rectangle { color:Color.popups.background; border.color:Color.accent; radius:Style.cornerRadius }
          contentItem:Column {
            spacing:4
            Controls.TextField { id:streamUrl; width:249; placeholderText:"Open URL"; onAccepted:{root.send("openurl",text); root.urlOpen=false; clear()} }
            Button { text:"Open"; foreground:root.fg; onClicked:{root.send("openurl",streamUrl.text); root.urlOpen=false; streamUrl.clear()} }
          }
        }
      }
      Rectangle { visible:root.eqOpen; width:1; height:root.fittedPanelHeight; color:root.fg; opacity:.18 }
      Column {
        id:eqColumn
        opacity:root.state.eq === true ? 1 : 0.4
        visible:root.eqOpen
        width:245
        height:root.fittedPanelHeight
        spacing:4
        Row {
          id:eqHeader
          width:parent.width
          Rectangle {
            id:eqToggle
            width:183; height:24
            radius:Style.cornerRadius
            color:eqToggleMouse.containsMouse ? Style.hoverFillFor(root.fg,Color.accent) : "transparent"
            Text {
              anchors.left:parent.left; anchors.leftMargin:eqToggleMouse.containsMouse ? 5 : 0
              anchors.verticalCenter:parent.verticalCenter
              anchors.verticalCenterOffset:eqToggleMouse.pressed ? 1 : 0
              text:"Equalizer"; color:root.fg; font.pixelSize:13; font.bold:true
            }
            MouseArea {
              id:eqToggleMouse
              anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
              onClicked:root.send("eq",!root.state.eq)
            }
          }
          Item { width:26; height:24; Button { id:savePresetButton; width:26; height:24; text:"+"; fontSize:12; horizontalPadding:2; visible:root.state.eqCustom === true; foreground:root.fg; onClicked:{root.savePresetOpen=!root.savePresetOpen; if (root.savePresetOpen) presetName.forceActiveFocus()} } }
          Button { text:"◂"; fontSize:12; verticalPadding:2; foreground:root.fg; onClicked:root.eqOpen=false }
        }
        Row {
          id:eqActions
          width:parent.width; spacing:4
          Button {
            id:presetSelector
            width:parent.width; height:28
            foreground:root.fg; selected:root.presetsOpen
            Text { anchors.left:parent.left; anchors.leftMargin:6; anchors.right:parent.right; anchors.rightMargin:20; anchors.verticalCenter:parent.verticalCenter; text:root.state.eqPresetName || "Custom"; textFormat:Text.PlainText; elide:Text.ElideRight; color:root.fg; font.pixelSize:12 }
            Text { anchors.right:parent.right; anchors.rightMargin:6; anchors.verticalCenter:parent.verticalCenter; text:"▾"; color:root.fg; font.pixelSize:12 }
            onClicked:root.presetsOpen=!root.presetsOpen
          }
        }
        Controls.Popup {
          id:presetDropdown
          scale:root.uiScale
          parent:presetSelector
          y:parent.height+4
          width:eqColumn.width; padding:6
          height:contentItem.implicitHeight+padding*2
          visible:root.opened && root.eqOpen && root.presetsOpen
          focus:true
          closePolicy:Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
          onClosed:root.presetsOpen=false
          background:Rectangle { color:Color.popups.background; border.color:Color.accent; border.width:1; radius:Style.cornerRadius }
          contentItem:Column {
            spacing:3
            Repeater {
              model:root.state.eqPresets || []
              Rectangle {
                required property var modelData
                width:parent.width-8; height:30
                radius:Style.cornerRadius
                color:presetHover.hovered ? Style.hoverFillFor(root.fg,Color.accent) : modelData.id===root.state.eqPresetId ? Style.selectedFillFor(root.fg,Color.accent) : "transparent"
                HoverHandler { id:presetHover }
                MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{root.send("preset",modelData.id); root.presetsOpen=false; root.savePresetOpen=false} }
                Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:parent.width-(modelData.user ? 28 : 12); text:modelData.name; textFormat:Text.PlainText; elide:Text.ElideRight; color:root.fg; font.pixelSize:12; font.bold:modelData.id===root.state.eqPresetId }
                Button { visible:modelData.user; anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter; width:20; height:28; text:"×"; foreground:root.fg; fontSize:12; verticalPadding:2; horizontalPadding:0; onClicked:root.send("delete-preset",modelData.id) }
              }
            }
          }
        }
        Controls.Popup {
          id:savePresetPopup
          scale:root.uiScale
          parent:savePresetButton
          x:-220; y:parent.height+4
          width:260; padding:8
          height:contentItem.implicitHeight+padding*2
          visible:root.opened && root.eqOpen && root.savePresetOpen && root.state.eqCustom === true
          focus:true
          closePolicy:Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
          onClosed:root.savePresetOpen=false
          background:Rectangle { color:Color.popups.background; border.color:Color.accent; border.width:1; radius:Style.cornerRadius }
          contentItem:Column {
            spacing:6
            Text { text:"Save custom preset"; color:root.fg }
            Controls.TextField { id:presetName; width:244; placeholderText:"Preset name"; onAccepted:{root.send("save-preset",text); root.savePresetOpen=false; clear()} }
            Button { text:"Save"; foreground:root.fg; onClicked:{root.send("save-preset",presetName.text); root.savePresetOpen=false; presetName.clear()} }
          }
        }
        Text { id:preampLabel; text:"Preamp: " + Number(root.state.preamp || 0).toFixed(1) + " dB"; color:root.fg; font.pixelSize:12 }
        Controls.Slider { id:preampSlider; width:parent.width; height:20; from:-12; to:12; value:root.state.preamp || 0; onMoved:root.send("preamp",value) }
        Row {
          id:eqBands
          spacing:2
          height:Math.max(40, root.fittedPanelHeight-eqHeader.height-eqActions.height-preampLabel.height-preampSlider.height-eqColumn.spacing*4)
          Repeater {
            model:["31","63","125","250","500","1k","2k","4k","8k","16k"]
            Column {
              required property string modelData
              required property int index
              width:22
              Text { id:bandValue; width:parent.width; horizontalAlignment:Text.AlignHCenter; text:root.state.bands ? Number(root.state.bands[index]).toFixed(0) : "0"; color:root.fg; font.pixelSize:10 }
              Controls.Slider { width:22; height:Math.max(20,eqBands.height-bandValue.height-bandFrequency.height); orientation:Qt.Vertical; from:-12; to:12; value:root.state.bands ? root.state.bands[index] : 0; onMoved:root.send("band",value,index) }
              Text { id:bandFrequency; width:parent.width; horizontalAlignment:Text.AlignHCenter; text:modelData; color:root.fg; font.pixelSize:10 }
            }
          }
        }
      }
      Rectangle { visible:root.playlistOpen; width:1; height:root.fittedPanelHeight; color:root.fg; opacity:.18 }
      Column {
        id:playlistColumn
        visible:root.playlistOpen
        width:245
        height:root.fittedPanelHeight
        spacing:8
        Row {
          id:playlistHeader
          width:parent.width; spacing:2
          Text { text:"Playlist"; color:root.fg; font.pixelSize:13; font.bold:true; width:parent.width-editOrderButton.width-playlistCollapse.width-parent.spacing*2 }
          Button { id:editOrderButton; text:"↕"; width:24; fontSize:13; horizontalPadding:2; verticalPadding:2; foreground:root.fg; selected:root.editOrder; onClicked:{root.editOrder=!root.editOrder; root.renameUri=""} }
          Button { id:playlistCollapse; text:"◂"; fontSize:12; verticalPadding:2; foreground:root.fg; onClicked:{root.playlistOpen=false; root.editOrder=false} }
        }
        Button {
          id:playlistSelector
          fontSize:12; verticalPadding:3; horizontalPadding:4
          width:parent.width; height:28
          clip:true
          Text { anchors.left:parent.left; anchors.leftMargin:6; anchors.right:parent.right; anchors.rightMargin:20; anchors.verticalCenter:parent.verticalCenter; text:root.state.playlistName || "Playlist"; textFormat:Text.PlainText; elide:Text.ElideRight; color:root.fg; font.pixelSize:12 }
          Text { anchors.right:parent.right; anchors.rightMargin:6; anchors.verticalCenter:parent.verticalCenter; text:"▾"; color:root.fg; font.pixelSize:12 }
          foreground:root.fg
          selected:root.listsOpen
          onClicked:{root.listsOpen=!root.listsOpen; if (root.listsOpen) root.send("list-playlists")}
        }
        Controls.Popup {
          id:listsDropdown
          scale:root.uiScale
          parent:playlistSelector
          y:parent.height+4
          width:playlistColumn.width; padding:6
          height:contentItem.implicitHeight+padding*2
          visible:root.opened && root.playlistOpen && root.listsOpen
          focus:true
          closePolicy:Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
          onClosed:{root.listsOpen=false; root.newListOpen=false; root.renameListTarget=null}
          background:Rectangle { color:Color.popups.background; border.color:Color.accent; border.width:1; radius:Style.cornerRadius }
          contentItem:Column {
            spacing:3
          Row {
            width:parent.width; spacing:2
            Button { width:parent.width-26; text:"+ New List"; fontSize:12; leftAlign:true; horizontalPadding:4; foreground:root.fg; onClicked:{root.renameListTarget=null; root.newListOpen=true; listName.forceActiveFocus()} }
            Button { width:24; text:"…"; fontSize:12; horizontalPadding:2; foreground:root.fg; selected:root.fullListNames; tooltipText:root.fullListNames ? "Compact names" : "Show full names"; onClicked:root.fullListNames=!root.fullListNames }
          }
          Row {
            width:parent.width
            visible:root.newListOpen
            spacing:4
            Controls.TextField { id:listName; width:parent.width-createListButton.width-parent.spacing; placeholderText:"New list name"; onAccepted:{root.send("create-list",text); clear(); root.newListOpen=false; root.listsOpen=false} }
            Button { id:createListButton; text:"✓"; width:24; horizontalPadding:2; tooltipText:"Create list"; foreground:root.fg; onClicked:{root.send("create-list",listName.text); listName.clear(); root.newListOpen=false; root.listsOpen=false} }
          }
          Column {
            width:parent.width
            visible:root.renameListTarget !== null
            spacing:4
            Text { text:"Rename playlist"; color:root.fg; font.pixelSize:12 }
            Row {
              width:parent.width
              spacing:4
              Controls.TextField {
                id:playlistRenameText
                width:parent.width-48
                placeholderText:"Playlist name"
                selectByMouse:true
                onAccepted:root.saveListName()
                Keys.onEscapePressed:function(event) { root.renameListTarget=null; event.accepted=true }
              }
              Button { width:20; text:"✓"; tooltipText:"Save name"; foreground:root.fg; horizontalPadding:2; onClicked:root.saveListName() }
              Button { width:20; text:"×"; tooltipText:"Cancel"; foreground:root.fg; horizontalPadding:2; onClicked:root.renameListTarget=null }
            }
          }
          ListView {
            id:playlistCatalog
            width:parent.width; height:Math.min(root.fullListNames ? 240 : 150, contentHeight); clip:true
            model:root.state.playlists || []
            Controls.ScrollBar.vertical: Controls.ScrollBar {}
            delegate:Rectangle {
              required property var modelData
              width:ListView.view.width-8
              height:Math.max(30, playlistLabel.implicitHeight+10)
              radius:Style.cornerRadius
              color:catalogHover.hovered ? Style.hoverFillFor(root.fg,Color.accent) : modelData.index===root.state.playlistIndex ? Style.selectedFillFor(root.fg,Color.accent) : "transparent"
              HoverHandler { id:catalogHover }
              MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:{root.send("playlist",modelData.index); root.listsOpen=false; root.renameUri=""} }
              Text {
                id:playlistLabel
                x:6; anchors.verticalCenter:parent.verticalCenter
                width:parent.width-48
                text:modelData.name; textFormat:Text.PlainText
                wrapMode:root.fullListNames ? Text.WrapAnywhere : Text.NoWrap
                elide:root.fullListNames ? Text.ElideNone : Text.ElideRight
                color:root.fg; font.pixelSize:12; font.bold:modelData.index===root.state.playlistIndex
              }
              Button { anchors.right:parent.right; anchors.rightMargin:20; anchors.verticalCenter:parent.verticalCenter; width:20; height:28; text:"✎"; fontSize:12; foreground:root.fg; tooltipText:"Rename playlist"; verticalPadding:2; horizontalPadding:0; onClicked:{root.newListOpen=false; root.renameListTarget={index:modelData.index,name:modelData.name}; playlistRenameText.text=modelData.name; playlistRenameText.forceActiveFocus(); playlistRenameText.selectAll()} }
              Button { anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter; width:20; height:28; text:"×"; fontSize:12; foreground:root.fg; tooltipText:"Delete playlist"; verticalPadding:2; horizontalPadding:0; onClicked:root.send("delete-list",modelData) }
            }
          }
          }
        }
        ListView {
          id:trackList
          width:parent.width; height:Math.max(32,root.fittedPanelHeight-playlistHeader.height-playlistSelector.height-addTracks.height-playlistColumn.spacing*3); clip:true
          model:root.state.songEntries || []
          Controls.ScrollBar.vertical: Controls.ScrollBar {}
          delegate: Rectangle {
            required property var modelData
            required property int index
            width:ListView.view.width-8; height:32; radius:Style.cornerRadius
            color:index === root.state.position ? Qt.alpha(Color.accent,.2) : "transparent"
            Text { x:6; anchors.verticalCenter:parent.verticalCenter; width:parent.width-48; text:(index+1)+". "+modelData.label; color:root.fg; elide:Text.ElideRight; font.pixelSize:12; textFormat:Text.PlainText }
            MouseArea { anchors.fill:parent; onDoubleClicked:if (!root.editOrder) root.send("jump",index) }
            Button { anchors.right:parent.right; anchors.rightMargin:20; anchors.verticalCenter:parent.verticalCenter; width:20; height:28; text:root.editOrder ? "↑" : "✎"; enabled:!root.editOrder || (!root.movePending && index>0); fontSize:12; foreground:root.fg; verticalPadding:2; horizontalPadding:0; onClicked:{if (root.editOrder) root.moveEntry(index,index-1); else {root.renameUri=modelData.uri; renameText.text=modelData.label; renameText.forceActiveFocus(); renameText.selectAll()}} }
            Button { anchors.right:parent.right; anchors.verticalCenter:parent.verticalCenter; width:20; height:28; text:root.editOrder ? "↓" : "×"; enabled:!root.editOrder || (!root.movePending && index < (root.state.songEntries || []).length-1); fontSize:12; foreground:root.fg; verticalPadding:2; horizontalPadding:0; onClicked:{if (root.editOrder) root.moveEntry(index,index+1); else root.send("delete",index)} }
          }
        }
        Controls.Popup {
          parent:playlistColumn
          y:parent.height+4; width:parent.width; padding:6; scale:root.uiScale
          visible:root.opened && root.playlistOpen && root.renameUri !== ""
          focus:true
          closePolicy:Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
          onClosed:root.renameUri=""
          background:Rectangle { color:Color.popups.background; border.color:Color.accent; radius:Style.cornerRadius }
          contentItem:Row {
            spacing:3
            Controls.TextField { id:renameText; width:parent.width-46; placeholderText:"Display name"; onAccepted:{root.send("rename-entry",{uri:root.renameUri,label:text}); root.renameUri=""} }
            Button { width:20; text:"✓"; horizontalPadding:2; foreground:root.fg; onClicked:{root.send("rename-entry",{uri:root.renameUri,label:renameText.text}); root.renameUri=""} }
            Button { width:20; text:"×"; horizontalPadding:2; foreground:root.fg; onClicked:root.renameUri="" }
          }
        }
        Row {
          id:addTracks
          width:parent.width
          spacing:2
          Controls.TextField { id:url; width:parent.width-addUrlButton.width-addFileButton.width-parent.spacing*2; placeholderText:"Radio / YouTube URL or file"; onAccepted:{root.send("add",text); clear()} }
          Button { id:addUrlButton; text:"+"; fontSize:12; horizontalPadding:3; foreground:root.fg; onClicked:{root.send("add",url.text); url.clear()} }
          Button { id:addFileButton; text:"File"; fontSize:11; horizontalPadding:3; foreground:root.fg; onClicked:{root.send("files"); root.close()} }
        }
      }
    }
  }
}
