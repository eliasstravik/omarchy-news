pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var feed: null
  property var post: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property var scrollPositions: ({})
  property string activeKey: ""

  signal backRequested()
  signal openUrlRequested(string url)
  signal copyRequested()

  readonly property color dim: Util.alpha(foreground, 0.55)
  readonly property var blocks: post ? Model.htmlToBlocks(String(post.contentHtml || "")) : []

  implicitHeight: Math.min(Style.space(600), articleColumn.implicitHeight + Style.space(156))

  function rememberScroll() {
    if (activeKey === "") return
    var next = Object.assign({}, scrollPositions)
    next[activeKey] = articleFlick.contentY
    scrollPositions = next
  }

  function restoreScroll() {
    var saved = Number(scrollPositions[activeKey] || 0)
    articleFlick.contentY = Math.max(0, Math.min(saved, Math.max(0, articleFlick.contentHeight - articleFlick.height)))
  }

  function scrollBy(distance) {
    articleFlick.contentY = Math.max(0, Math.min(articleFlick.contentY + distance, Math.max(0, articleFlick.contentHeight - articleFlick.height)))
  }

  function pageBy(direction) {
    scrollBy(direction * Math.max(Style.space(56), articleFlick.height - Style.space(56)))
  }

  function scrollToTop() {
    articleFlick.contentY = 0
  }

  function scrollToBottom() {
    articleFlick.contentY = Math.max(0, articleFlick.contentHeight - articleFlick.height)
  }

  function safeInline(text) {
    return Model.sanitizeInline(String(text || ""))
  }

  function imageSource(url) {
    return feed && Model.isSafeHttpUrl(url) ? feed.imagePath(url) : ""
  }

  onPostChanged: {
    rememberScroll()
    activeKey = post ? String(post.key || "") : ""
    Qt.callLater(restoreScroll)
  }

  Column {
    id: layout
    anchors.fill: parent
    spacing: Style.space(12)

    Item {
      id: headerRow
      width: parent.width
      implicitHeight: Math.max(backButton.implicitHeight, meta.implicitHeight)

      PanelActionButton {
        id: backButton
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅁"
        tooltipText: "Back (Backspace)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.backRequested()
      }

      Text {
        id: meta
        anchors.left: backButton.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.post
          ? String(root.post.author || "") + " · " + Model.formatDate(Number(root.post.publishedAt || 0)) + " · " + String(root.post.readingMinutes || "1 min read")
          : ""
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      id: titleText
      width: parent.width
      text: root.post ? String(root.post.title || "") : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.weight: Font.DemiBold
      wrapMode: Text.WordWrap
    }

    PanelSeparator {
      id: separator
      foreground: root.foreground
    }

    Flickable {
      id: articleFlick
      width: parent.width
      height: Math.max(0, root.height - headerRow.height - titleText.height - separator.height - footer.height - Style.space(48))
      clip: true
      contentWidth: width
      contentHeight: articleColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: articleColumn
        width: articleFlick.width
        spacing: Style.space(10)

        Repeater {
          model: root.blocks

          Item {
            id: blockDelegate
            required property var modelData
            width: parent ? parent.width : 0
            implicitHeight: Math.max(
              paragraph.visible ? paragraph.implicitHeight : 0,
              heading.visible ? heading.implicitHeight : 0,
              quote.visible ? quote.implicitHeight : 0,
              list.visible ? list.implicitHeight : 0,
              codeSurface.visible ? codeSurface.implicitHeight : 0,
              imageBlock.visible ? imageBlock.implicitHeight : 0,
              rule.visible ? rule.height : 0)

            Text {
              id: paragraph
              visible: blockDelegate.modelData.type === "p"
              width: parent.width
              text: root.safeInline(blockDelegate.modelData.text)
              textFormat: Text.StyledText
              color: root.foreground
              linkColor: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              lineHeight: 1.35
              lineHeightMode: Text.ProportionalHeight
              onLinkActivated: function(link) { root.openUrlRequested(link) }
            }

            Text {
              id: heading
              visible: blockDelegate.modelData.type === "h"
              width: parent.width
              text: String(blockDelegate.modelData.text || "")
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.weight: Font.DemiBold
              wrapMode: Text.WordWrap
            }

            Item {
              id: quote
              visible: blockDelegate.modelData.type === "quote"
              width: parent.width
              implicitHeight: quoteText.implicitHeight + Style.space(8)

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.space(2)
                color: root.accent
              }

              Text {
                id: quoteText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: String(blockDelegate.modelData.text || "")
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.italic: true
                wrapMode: Text.WordWrap
                lineHeight: 1.35
                lineHeightMode: Text.ProportionalHeight
              }
            }

            Column {
              id: list
              visible: blockDelegate.modelData.type === "ul" || blockDelegate.modelData.type === "ol"
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: list.visible && Array.isArray(blockDelegate.modelData.items) ? blockDelegate.modelData.items : []

                Item {
                  required property var modelData
                  required property int index
                  width: parent ? parent.width : 0
                  implicitHeight: listText.implicitHeight

                  Text {
                    id: marker
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: Style.space(24)
                    text: blockDelegate.modelData.type === "ol" ? (index + 1) + "." : "•"
                    textFormat: Text.PlainText
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    id: listText
                    anchors.left: marker.right
                    anchors.right: parent.right
                    text: root.safeInline(modelData)
                    textFormat: Text.StyledText
                    color: root.foreground
                    linkColor: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                    lineHeightMode: Text.ProportionalHeight
                    onLinkActivated: function(link) { root.openUrlRequested(link) }
                  }
                }
              }
            }

            BorderSurface {
              id: codeSurface
              visible: blockDelegate.modelData.type === "code"
              width: parent.width
              implicitHeight: codeText.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Text {
                id: codeText
                anchors.fill: parent
                anchors.margins: Style.space(8)
                text: String(blockDelegate.modelData.text || "")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
              }
            }

            Column {
              id: imageBlock
              visible: blockDelegate.modelData.type === "img"
              width: parent.width
              spacing: Style.space(5)

              ClippingRectangle {
                width: parent.width
                height: articleImage.status === Image.Ready && articleImage.implicitWidth > 0
                  ? Math.min(Style.space(240), width * articleImage.implicitHeight / articleImage.implicitWidth)
                  : Style.space(160)
                radius: Style.cornerRadius
                color: Util.alpha(root.foreground, 0.06)

                Image {
                  id: articleImage
                  anchors.fill: parent
                  source: root.imageSource(blockDelegate.modelData.src)
                  asynchronous: true
                  cache: true
                  fillMode: Image.PreserveAspectFit
                  visible: status === Image.Ready
                  opacity: visible ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 140 } }
                }
              }

              Text {
                visible: String(blockDelegate.modelData.alt || "") !== ""
                width: parent.width
                text: String(blockDelegate.modelData.alt || "")
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Rectangle {
              id: rule
              visible: blockDelegate.modelData.type === "hr"
              width: parent.width
              height: Style.space(1)
              color: Util.alpha(root.foreground, 0.18)
            }
          }
        }
      }
    }

    Text {
      id: footer
      width: parent.width
      text: "Backspace back · o browser · c copy · n/p next/prev"
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
