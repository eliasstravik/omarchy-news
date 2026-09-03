import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "io.github.eliasstravik.omarchy-news"
  ipcTarget: moduleName
  manageIpc: false

  property var unseenKeysAtOpen: []
  property int cursorIndex: 0
  property bool cursorActive: false
  property string copiedKey: ""
  property bool helpOpen: false
  property var undoReadMap: null
  property int undoCount: 0
  property int undoRemainingMs: 0
  property bool undoPaused: false
  property var currentPost: null
  readonly property bool reading: currentPost !== null
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

  function selectedPost() {
    if (!feed || feed.posts.length === 0) return null
    cursorIndex = Math.max(0, Math.min(cursorIndex, feed.posts.length - 1))
    return feed.posts[cursorIndex]
  }

  function revealOrMoveCursor(delta) {
    if (!feed || feed.posts.length === 0) return
    if (!cursorActive) {
      cursorActive = true
      cursorIndex = 0
      return
    }
    cursorIndex = Math.max(0, Math.min(feed.posts.length - 1, cursorIndex + delta))
  }

  function selectCursor(index) {
    if (!feed || feed.posts.length === 0) return
    cursorIndex = Math.max(0, Math.min(feed.posts.length - 1, Number(index)))
    cursorActive = true
  }

  function jumpCursor(index) {
    selectCursor(index)
  }

  function openSelectedReader() {
    var post = selectedPost()
    if (!post || !feed) return
    feed.markRead(post.key)
    currentPost = post
  }

  function openSelectedInBrowser(closePanel) {
    var post = selectedPost()
    if (!post || !feed || !Model.isSafeHttpUrl(post.link)) return
    feed.markRead(post.key)
    Quickshell.execDetached(["omarchy-launch-browser", String(post.link)])
    if (closePanel) close()
  }

  function copySelectedLink() {
    var post = selectedPost()
    if (!post || !Model.isSafeHttpUrl(post.link)) return
    Quickshell.execDetached(["wl-copy", String(post.link)])
    copiedKey = String(post.key || "")
    copyTimer.restart()
  }

  function toggleSelectedRead() {
    var post = selectedPost()
    if (post && feed) feed.toggleRead(post.key)
  }

  function discardUndo() {
    undoTimer.stop()
    undoReadMap = null
    undoCount = 0
    undoRemainingMs = 0
    undoPaused = false
  }

  function markAllWithUndo() {
    if (!feed || feed.posts.length === 0) return
    discardUndo()
    undoCount = feed.unreadCount
    undoReadMap = feed.markAllRead()
    if (undoCount > 0) {
      undoRemainingMs = 5000
      undoTimer.start()
    }
  }

  function undoMarkAll() {
    if (!feed || undoReadMap === null) return
    feed.restoreRead(undoReadMap)
    discardUndo()
  }

  function refreshFeed() {
    discardUndo()
    if (feed) feed.refresh()
  }

  function activateRow(index, buttonCode) {
    selectCursor(index)
    if (buttonCode === Qt.MiddleButton || buttonCode === Qt.RightButton) openSelectedInBrowser(false)
    else openSelectedReader()
  }

  function handleTextKey(text) {
    if (reading) {
      if (text === "n") moveReaderPost(1)
      else if (text === "p") moveReaderPost(-1)
      else if (text === "o") openSelectedInBrowser(false)
      else if (text === "c") copySelectedLink()
      else if (text === "g") readerPage.scrollToTop()
      else if (text === "G") readerPage.scrollToBottom()
      return
    }
    if (text === "m") toggleSelectedRead()
    else if (text === "o") openSelectedInBrowser(true)
    else if (text === "c") copySelectedLink()
    else if (text === "A") markAllWithUndo()
    else if (text === "u") undoMarkAll()
    else if (text === "r") refreshFeed()
    else if (text === "g") jumpCursor(0)
    else if (text === "G" && feed) jumpCursor(feed.posts.length - 1)
    else if (text === "?") helpOpen = !helpOpen
  }

  function closeReader() {
    if (!reading) return
    readerPage.rememberScroll()
    currentPost = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function moveReaderPost(delta) {
    if (!feed || feed.posts.length === 0) return
    readerPage.rememberScroll()
    cursorIndex = Math.max(0, Math.min(feed.posts.length - 1, cursorIndex + delta))
    currentPost = feed.posts[cursorIndex]
    feed.markRead(currentPost.key)
  }

  function openSafeUrl(url) {
    if (!Model.isSafeHttpUrl(url)) return
    Quickshell.execDetached(["omarchy-launch-browser", String(url)])
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
      cursorActive = false
      copiedKey = ""
      helpOpen = false
      currentPost = null
      discardUndo()
      return
    }
    cursorIndex = 0
    cursorActive = false
    helpOpen = false
    currentPost = null
    if (feed) {
      unseenKeysAtOpen = unseenPostKeys()
      feed.markSeen(allPostKeys())
      feed.refreshIfStale(300)
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Connections {
    target: root.feed
    function onPostsReplaced() {
      if (!root.feed || root.feed.posts.length === 0) {
        root.cursorIndex = 0
        root.cursorActive = false
      } else root.cursorIndex = Math.min(root.cursorIndex, root.feed.posts.length - 1)
    }
  }

  Timer {
    id: copyTimer
    interval: 1500
    onTriggered: root.copiedKey = ""
  }

  Shortcut {
    enabled: root.opened && root.reading
    sequence: "Backspace"
    onActivated: root.closeReader()
  }

  Shortcut {
    enabled: root.opened && root.reading
    sequence: "Shift+Space"
    onActivated: readerPage.pageBy(-1)
  }

  Timer {
    id: undoTimer
    interval: 50
    repeat: true
    onTriggered: {
      if (root.undoPaused) return
      root.undoRemainingMs = Math.max(0, root.undoRemainingMs - interval)
      if (root.undoRemainingMs === 0) root.discardUndo()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openOnInstances() }
    function close(): void { root.closeOnInstances() }
    function show(): void { root.openOnInstances() }
    function hide(): void { root.closeOnInstances() }
    function toggle(): void { root.toggleOnInstances() }
    function refresh(): string { root.refreshFeed(); return "ok" }
    function markAllRead(): string { root.markAllWithUndo(); return "ok" }
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
    contentHeight: panel.fittedContentHeight(pageHost.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: false
      onMoveRequested: function(dx, dy) {
        if (root.reading) {
          if (dy !== 0) readerPage.scrollBy(dy * Style.space(56))
          else if (dx < 0) root.closeReader()
          return
        }
        if (root.helpOpen) return
        if (dy !== 0) root.revealOrMoveCursor(dy)
        else if (dx > 0) root.openSelectedReader()
      }
      onActivateRequested: {
        if (root.reading) readerPage.pageBy(1)
        else root.openSelectedReader()
      }
      onCloseRequested: {
        if (root.reading) root.closeReader()
        else if (root.helpOpen) root.helpOpen = false
        else root.close()
      }
      onDeleteRequested: if (!root.reading) root.toggleSelectedRead()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { root.handleTextKey(text) }

      Item {
        id: pageHost
        anchors.fill: parent
        clip: true
        implicitHeight: root.reading ? readerPage.implicitHeight : listPage.implicitHeight

        ListPage {
          id: listPage
          width: parent.width
          height: parent.height
          x: root.reading ? -width * 0.3 : 0
          opacity: root.reading ? 0 : 1
          enabled: !root.reading
          feed: root.feed
          posts: root.feed ? root.feed.posts : []
          unseenKeys: root.unseenKeysAtOpen
          cursorIndex: root.cursorIndex
          cursorActive: root.cursorActive
          copiedKey: root.copiedKey
          helpOpen: root.helpOpen
          undoVisible: root.undoReadMap !== null
          undoCount: root.undoCount
          undoProgress: root.undoRemainingMs / 5000
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onCursorRequested: function(index) { root.selectCursor(index) }
          onRowActivated: function(index, buttonCode) { root.activateRow(index, buttonCode) }
          onRefreshRequested: root.refreshFeed()
          onMarkAllRequested: root.markAllWithUndo()
          onUndoRequested: root.undoMarkAll()
          onUndoHovered: function(hovered) { root.undoPaused = hovered }
          onHelpRequested: root.helpOpen = !root.helpOpen

          Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        ReaderPage {
          id: readerPage
          width: parent.width
          height: parent.height
          x: root.reading ? 0 : width
          opacity: root.reading ? 1 : 0
          enabled: root.reading
          feed: root.feed
          post: root.currentPost
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onBackRequested: root.closeReader()
          onOpenUrlRequested: function(url) { root.openSafeUrl(url) }
          onCopyRequested: root.copySelectedLink()

          Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: 160 } }
        }
      }
    }
  }
}
