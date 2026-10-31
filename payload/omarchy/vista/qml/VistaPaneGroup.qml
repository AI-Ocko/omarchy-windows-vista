import QtQuick
import qs.Commons

// VistaPaneGroup: an ExplorerBar task-pane group -- the head art (SizingMargins
// 3,106,3,1) with a bold Tahoma title, then the background art behind its
// VistaPaneLinks. `special` picks the Special group's art and colours.
Column {
  id: group

  property string title: ""
  property bool special: false
  default property alias links: groupBody.data

  width: parent ? parent.width : 0

  VistaArt {
    width: parent.width
    height: Style.space(25)
    source: VistaScheme.art(group.special ? "pane-special-head" : "pane-normal-head")
    margins: [3, 106, 3, 1]
    Text {
      x: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: Style.space(1)
      text: group.title
      color: group.special ? VistaScheme.sc.specialHead : VistaScheme.sc.normalHead
      font.family: "Tahoma"
      font.bold: true
      font.pixelSize: Style.font.bodySmall
    }
  }
  VistaArt {
    width: parent.width
    height: groupBody.implicitHeight + Style.space(16)
    source: VistaScheme.art(group.special ? "pane-special-bg" : "pane-normal-bg")
    margins: [3, 3, 3, 3]
    Column {
      id: groupBody
      x: Style.space(12)
      y: Style.space(8)
      width: parent.width - Style.space(24)
      spacing: Style.space(2)
    }
  }
}
