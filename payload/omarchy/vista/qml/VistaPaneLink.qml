import QtQuick
import qs.Commons

// VistaPaneLink: an Explorer task-pane link -- 16 px icon and Tahoma 8 in the
// scheme's NormalGroup TextColor, underlined on hover. Goes in an
// VistaPaneGroup; `enabled: false` draws it in GrayText and ignores clicks.
Item {
  id: link

  property string text: ""
  property url iconSource: ""
  signal activated()

  width: parent ? parent.width : 0
  height: Style.space(20)

  Image {
    id: linkIcon
    width: Style.space(16)
    height: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    source: link.iconSource
    opacity: link.enabled ? 1 : 0.5
  }
  Text {
    anchors.left: linkIcon.right
    anchors.leftMargin: Style.space(6)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: link.text
    elide: Text.ElideRight
    color: link.enabled ? VistaScheme.sc.normalText : VistaScheme.sc.gray
    font.family: "Segoe UI"
    font.pixelSize: Style.font.bodySmall
    font.underline: link.enabled && linkMouse.containsMouse
  }
  MouseArea {
    id: linkMouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: link.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: link.activated()
  }
}
