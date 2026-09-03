import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "io.github.eliasstravik.omarchy-news"
  ipcTarget: moduleName
  manageIpc: false

  property var unseenKeysAtOpen: []
  readonly property var feed: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property int unseenCount: feed ? feed.unseenCount : 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barIconColor: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function syncServiceSettings() {
    if (feed) feed.settings = settings
  }

  function allPostKeys() {
    var keys = []
    if (!feed) return keys
    for (var i = 0; i < feed.posts.length; i++) keys.push(String(feed.posts[i].key || ""))
    return keys
  }

  function unseenPostKeys() {
    var keys = []
    if (!feed) return keys
    for (var i = 0; i < feed.posts.length; i++) {
      var key = String(feed.posts[i].key || "")
      if (key !== "" && feed.persisted.seen[key] === undefined) keys.push(key)
    }
    return keys
  }

  function openOnInstances() {
    var widgets = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < widgets.length; i++) if (widgets[i] && typeof widgets[i].open === "function") widgets[i].open()
  }

  function closeOnInstances() {
    var widgets = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < widgets.length; i++) if (widgets[i] && typeof widgets[i].close === "function") widgets[i].close()
  }

  function toggleOnInstances() {
    var widgets = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < widgets.length; i++) if (widgets[i] && typeof widgets[i].toggle === "function") widgets[i].toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onFeedChanged: syncServiceSettings()
  onSettingsChanged: syncServiceSettings()
  onOpenedChanged: {
    if (!opened) {
      unseenKeysAtOpen = []
      return
    }
    if (feed) {
      unseenKeysAtOpen = unseenPostKeys()
      feed.markSeen(allPostKeys())
      feed.refreshIfStale(300)
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openOnInstances() }
    function close(): void { root.closeOnInstances() }
    function show(): void { root.openOnInstances() }
    function hide(): void { root.closeOnInstances() }
    function toggle(): void { root.toggleOnInstances() }
    function refresh(): string { if (root.feed) root.feed.refresh(); return "ok" }
    function markAllRead(): string { if (root.feed) root.feed.markAllRead(); return "ok" }
    function status(): string { return root.feed ? root.feed.statusJson() : JSON.stringify({ state: "service-disabled" }) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.unseenCount > 0
      ? "Omarchy News · " + root.unseenCount + " new"
      : "Omarchy News · up to date"
    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.fill: parent
          text: "󰑫"
          fontFamily: root.fontFamily
          fontSize: Style.bar.iconFont
          color: root.barIconColor
        }

        Rectangle {
          id: unreadDot
          width: Style.space(5)
          height: width
          radius: width / 2
          color: root.accent
          border.width: 1
          border.color: Color.bar.background
          anchors.top: parent.top
          anchors.right: parent.right
          visible: root.unseenCount > 0
          onVisibleChanged: if (visible) dotPop.restart()

          NumberAnimation {
            id: dotPop
            target: unreadDot
            property: "scale"
            from: 0.6
            to: 1
            duration: 200
            easing.type: Easing.OutBack
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) {
        if (root.feed) root.feed.refresh()
      } else if (buttonCode === Qt.RightButton) {
        Quickshell.execDetached(["omarchy-launch-browser", "https://omarchy.org/news"])
      } else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(emptyState.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: false
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" && root.feed) root.feed.refresh() }

      Column {
        id: emptyState
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "Omarchy News"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
        }

        Text {
          width: parent.width
          text: !root.feed
            ? "The Omarchy News service is not enabled."
            : (root.feed.fetching ? "Fetching the latest posts…"
              : (root.feed.state === "error" ? root.feed.errorText
                : root.feed.posts.length + " posts ready."))
          textFormat: Text.PlainText
          color: Util.alpha(root.foreground, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
