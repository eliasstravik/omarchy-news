pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

CursorSurface {
  id: root

  required property var post
  property bool unread: true
  property bool copied: false
  property color textColor: Color.foreground
  property color accentColor: Color.accent
  property string textFontFamily: Style.font.family
  property double nowMs: Date.now()

  signal selected()
  signal activated(int button)

  width: parent ? parent.width : implicitWidth
  implicitHeight: content.implicitHeight + Style.space(16)
  foreground: textColor
  accent: accentColor
  fill: Style.hoverFillFor(textColor, accentColor)
  currentFill: Style.selectedFillFor(textColor, accentColor)

  readonly property color dim: Util.alpha(textColor, 0.55)

  Item {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    implicitHeight: Math.max(labels.implicitHeight, Style.space(22))
    height: implicitHeight

    Item {
      id: unreadSlot
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(12)
      height: parent.height

      Rectangle {
        anchors.centerIn: parent
        width: Style.space(8)
        height: width
        radius: width / 2
        color: root.accentColor
        visible: root.unread
      }
    }

    Column {
      id: labels
      anchors.left: unreadSlot.right
      anchors.right: trailing.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: String(root.post.title || "")
        textFormat: Text.PlainText
        color: root.unread ? root.textColor : root.dim
        font.family: root.textFontFamily
        font.pixelSize: Style.font.body
        font.weight: root.unread ? Font.DemiBold : Font.Normal
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: String(root.post.author || "") + " · " + Model.relativeTime(Number(root.post.publishedAt || 0), root.nowMs)
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.textFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      id: trailing
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.copied ? "󰄬" : "󰅂"
      textFormat: Text.PlainText
      color: root.copied ? root.accentColor : root.dim
      font.family: root.textFontFamily
      font.pixelSize: Style.font.icon
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.selected()
    onClicked: function(mouse) { root.activated(mouse.button) }
  }
}
