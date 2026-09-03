pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var feed: null
  property var posts: []
  property var unseenKeys: []
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool helpOpen: false
  property bool undoVisible: false
  property int undoCount: 0
  property real undoProgress: 0
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property double nowMs: Date.now()

  signal cursorRequested(int index)
  signal rowActivated(int index, int button)
  signal refreshRequested()
  signal markAllRequested()
  signal undoRequested()
  signal undoHovered(bool hovered)
  signal helpRequested()

  readonly property color dim: Util.alpha(foreground, 0.55)
  readonly property var helpRows: [
    { key: "j / k  or  ↑ / ↓", action: "Move through posts" },
    { key: "Enter / Space / l / →", action: "Read the selected post" },
    { key: "o", action: "Open in the browser" },
    { key: "x / m", action: "Toggle read" },
    { key: "A", action: "Mark every post read" },
    { key: "u", action: "Undo mark all" },
    { key: "r", action: "Refresh" },
    { key: "g / G", action: "Jump to first or last" },
    { key: "Tab / Shift+Tab", action: "Switch bar panel" },
    { key: "Escape", action: "Close" }
  ]

  implicitHeight: Math.min(contentColumn.implicitHeight, Style.space(600))

  function containsKey(values, key) {
    for (var i = 0; i < values.length; i++) if (String(values[i]) === String(key)) return true
    return false
  }

  function rows(wantNew) {
    var result = []
    for (var i = 0; i < posts.length; i++) {
      var isNew = containsKey(unseenKeys, posts[i].key)
      if (isNew === wantNew) result.push({ post: posts[i], index: i })
    }
    return result
  }

  function isUnread(post) {
    return !feed || !feed.persisted || !feed.persisted.read || feed.persisted.read[String(post.key || "")] === undefined
  }

  function statusMeta() {
    if (!feed) return "SERVICE NOT ENABLED"
    if (feed.fetching) return "FETCHING…"
    if (feed.state === "error" && posts.length > 0) return "OFFLINE · CACHED"
    if (unseenKeys.length > 0) {
      var updated = Model.relativeTime(Number(feed.lastFetchAt || 0), nowMs)
      return unseenKeys.length + " NEW · UPDATED " + (updated === "now" ? "NOW" : updated.toUpperCase() + " AGO")
    }
    if (posts.length > 0) {
      var latest = Model.relativeTime(Number(posts[0].publishedAt || 0), nowMs)
      return "UP TO DATE · LAST POST " + (latest === "now" ? "NOW" : latest.toUpperCase() + " AGO")
    }
    return "FETCHING…"
  }

  function scrollCursorIntoView() {
    if (!cursorActive || helpOpen) return
    var item = null
    if (unseenKeys.length === 0) item = rowRepeater.itemAt(cursorIndex)
    var fresh = rows(true)
    for (var i = 0; !item && i < fresh.length; i++) {
      if (fresh[i].index === cursorIndex) item = newRepeater.itemAt(i)
    }
    var earlier = rows(false)
    for (var j = 0; !item && j < earlier.length; j++) {
      if (earlier[j].index === cursorIndex) item = earlierRepeater.itemAt(j)
    }
    if (!item) return
    var point = item.mapToItem(contentColumn, 0, 0)
    var top = point.y
    var bottom = top + item.height
    if (top < flick.contentY) flick.contentY = Math.max(0, top - Style.space(8))
    else if (bottom > flick.contentY + flick.height) flick.contentY = Math.min(flick.contentHeight - flick.height, bottom - flick.height + Style.space(8))
  }

  onCursorIndexChanged: Qt.callLater(scrollCursorIntoView)
  onCursorActiveChanged: Qt.callLater(scrollCursorIntoView)

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: contentColumn
      width: flick.width
      spacing: Style.space(12)

      PanelHero {
        width: parent.width
        title: "Omarchy News"
        meta: root.statusMeta()
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconSize: Style.font.displayLarge
        iconComponent: Component {
          Text {
            text: Qt.fontFamilies().indexOf("omarchy") >= 0 ? "" : "󰑫"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Qt.fontFamilies().indexOf("omarchy") >= 0 ? "omarchy" : root.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }
        trailingControl: Component {
          Row {
            spacing: Style.space(4)

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.refreshRequested()

              RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 800
                loops: Animation.Infinite
                running: root.feed ? root.feed.fetching : false
              }
            }

            PanelActionButton {
              iconText: "󰄬"
              tooltipText: "Mark all read (A)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.posts.length > 0
              onClicked: root.markAllRequested()
            }
          }
        }
      }

      PanelSeparator {
        foreground: root.foreground
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.helpOpen

        PanelSectionHeader {
          text: "CONTROLS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.helpRows

          Item {
            id: helpRow
            required property var modelData
            width: parent ? parent.width : 0
            implicitHeight: Math.max(keyText.implicitHeight, actionText.implicitHeight) + Style.space(8)

            Text {
              id: keyText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * 0.44
              text: String(helpRow.modelData.key)
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              wrapMode: Text.WordWrap
            }

            Text {
              id: actionText
              anchors.left: keyText.right
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: String(helpRow.modelData.action)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: !root.helpOpen && root.posts.length > 0

        PanelSectionHeader {
          visible: root.unseenKeys.length > 0
          text: "NEW"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          id: newRepeater
          model: root.unseenKeys.length > 0 ? root.rows(true) : []

          PostRow {
            required property var modelData
            post: modelData.post
            unread: root.isUnread(post)
            hasCursor: root.cursorActive && root.cursorIndex === modelData.index
            textColor: root.foreground
            accentColor: root.accent
            textFontFamily: root.fontFamily
            nowMs: root.nowMs
            onSelected: root.cursorRequested(modelData.index)
            onActivated: function(button) { root.rowActivated(modelData.index, button) }
          }
        }

        PanelSectionHeader {
          visible: root.unseenKeys.length > 0 && root.rows(false).length > 0
          text: "EARLIER"
          foreground: root.foreground
          fontFamily: root.fontFamily
          topPadding: Style.space(10)
        }

        Repeater {
          id: earlierRepeater
          model: root.unseenKeys.length > 0 ? root.rows(false) : []

          PostRow {
            required property var modelData
            post: modelData.post
            unread: root.isUnread(post)
            hasCursor: root.cursorActive && root.cursorIndex === modelData.index
            textColor: root.foreground
            accentColor: root.accent
            textFontFamily: root.fontFamily
            nowMs: root.nowMs
            onSelected: root.cursorRequested(modelData.index)
            onActivated: function(button) { root.rowActivated(modelData.index, button) }
          }
        }

        PanelSectionHeader {
          visible: root.unseenKeys.length === 0
          text: "LATEST"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          id: rowRepeater
          model: root.unseenKeys.length === 0 ? root.posts : []

          PostRow {
            required property var modelData
            required property int index
            post: modelData
            unread: root.isUnread(post)
            hasCursor: root.cursorActive && root.cursorIndex === index
            textColor: root.foreground
            accentColor: root.accent
            textFontFamily: root.fontFamily
            nowMs: root.nowMs
            onSelected: root.cursorRequested(index)
            onActivated: function(button) { root.rowActivated(index, button) }
          }
        }
      }

      BorderSurface {
        id: undoStrip
        visible: root.undoVisible && !root.helpOpen
        width: parent.width
        implicitHeight: undoText.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        color: Util.alpha(root.foreground, 0.04)
        borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

        Text {
          id: undoText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.margins: Style.space(8)
          text: "Marked " + root.undoCount + " posts as read · Undo (u)"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          width: parent.width * root.undoProgress
          height: Style.space(2)
          color: root.accent
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: root.undoHovered(containsMouse)
          onClicked: root.undoRequested()
        }
      }

      Text {
        visible: !root.helpOpen && root.posts.length === 0
        width: parent.width
        text: root.feed && root.feed.state === "error"
          ? "Couldn't reach omarchy.org. Press r to retry."
          : "Fetching the latest posts…"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.italic: true
        wrapMode: Text.WordWrap
      }

      Text {
        visible: !root.helpOpen && root.feed && root.feed.state === "error" && root.posts.length > 0
        width: parent.width
        text: root.feed ? root.feed.errorText : ""
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        text: root.helpOpen
          ? "? or Esc back"
          : "j/k move · ⏎ read · o browser · r refresh · ? more"
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.helpRequested()
        }
      }
    }
  }
}
