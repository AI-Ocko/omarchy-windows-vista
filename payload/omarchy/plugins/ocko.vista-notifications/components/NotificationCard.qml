// Notification card, as a Windows Vista balloon tip (ocko.vista-notifications).
// Same interface as omarchy.notifications' NotificationCard (properties,
// `hovered`, closeRequested / cardClicked) so the stock lifetime and click
// handling in Service.qml drive it unchanged.
//
// Layout follows Vista's tray balloon: user32 16 px information / warning /
// error icon and the bold title on one line, the balloon close button
// (Tooltip.Close, 3 frames) at the top right, the body underneath, Tahoma 8
// black on InfoWindow yellow. Urgent notifications get the warning icon; an
// app icon named *error* gets the error icon. The notification's own image
// (album art, screenshot preview) stays, left of the body; Nerd glyphs do not
// (Vista has none; the info icon stands in).

import QtQuick
import Quickshell
import qs.Commons
import "../NotificationLogic.js" as NotificationLogic
import "../../../vista/qml"

VistaBalloon {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  property double timestamp: 0
  property int cornerRadius: 0
  property string fontFamily: ""

  readonly property bool hovered: hoverTracker.hovered
  signal closeRequested()
  signal cardClicked()

  readonly property string iconKind: urgency === 2 ? "warning"
    : (/error|fail/i.test(appIcon) ? "error" : (/warn/i.test(appIcon) ? "warning" : "info"))
  readonly property string titleText: summary.length > 0 ? summary : app
  readonly property string sanitizedBody: NotificationLogic.sanitizeBody(body, app, appIcon)
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)
  readonly property string imageSource: {
    var v = String(image || "")
    if (!v) return ""
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    return v.charAt(0) === "/" ? Util.fileUrl(v) : ""
  }

  implicitWidth: Style.space(330)
  // Vista's tail points at the notification area; the bar's clock sits right
  // of the icons, so aim a little left of the balloon's right edge.
  tailX: width - Style.space(52)
  padding: Style.space(9)

  HoverHandler { id: hoverTracker; parent: root }

  // On the balloon itself, under the content, so the close button wins.
  MouseArea {
    parent: root
    z: -1
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.closeRequested()
      else root.cardClicked()
    }
  }

  contentHeight: cardColumn.implicitHeight

  Column {
    id: cardColumn
    width: root.contentArea.width
    spacing: Style.space(6)

    Item {
      width: parent.width
      height: Math.max(titleIcon.height, titleLabel.implicitHeight)

      Image {
        id: titleIcon
        width: Style.space(16)
        height: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        source: VistaScheme.sysIcon(root.iconKind, 16)
        smooth: true
      }
      Text {
        id: titleLabel
        anchors.left: titleIcon.right
        anchors.leftMargin: Style.space(6)
        anchors.right: closeButton.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        // A single line of plain text per the spec, as stock renders it.
        textFormat: Text.PlainText
        text: root.titleText
        elide: Text.ElideRight
        // Vista's balloon title: Segoe UI 12 pt in the main-instruction blue.
        color: VistaScheme.sc.instruction
        font.family: "Segoe UI"
        font.pixelSize: Style.space(16)
      }
      Item {
        id: closeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(17)
        height: Style.space(16)
        Image {
          anchors.fill: parent
          source: VistaScheme.art("balloon-close-" + (closeMouse.pressed ? 2 : closeMouse.containsMouse ? 1 : 0))
          smooth: true
        }
        MouseArea {
          id: closeMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: root.closeRequested()
        }
      }
    }

    Row {
      visible: root.sanitizedBody.length > 0 || bodyImage.visible
      width: parent.width
      spacing: Style.space(8)

      Image {
        id: bodyImage
        visible: root.imageSource !== "" && status !== Image.Error
        width: visible ? Style.space(48) : 0
        height: Style.space(48)
        source: root.imageSource
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        fillMode: Image.PreserveAspectFit
        asynchronous: true
      }
      Text {
        width: parent.width - (bodyImage.visible ? bodyImage.width + parent.spacing : 0)
        // StyledText on purpose (bodyMarkupSupported), stripped by
        // NotificationLogic exactly as stock does.
        text: root.styledBody
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: 6
        color: VistaScheme.infoText
        linkColor: "#0000FF"
        font.family: "Segoe UI"
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
