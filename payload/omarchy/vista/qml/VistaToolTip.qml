import QtQuick
import qs.Commons

// VistaToolTip: a tooltips_class32 tip -- InfoWindow yellow (hivedef.inf), a
// 1 px black edge, Tahoma 8 in InfoText, 2 px across and 1 px down of
// padding. The owner positions it and drives `visible`.
Rectangle {
  property alias text: label.text

  implicitWidth: label.implicitWidth + Style.space(6)
  implicitHeight: label.implicitHeight + Style.space(4)
  width: implicitWidth
  height: implicitHeight
  color: VistaScheme.infoWindow
  border.width: 1
  border.color: "#000000"

  Text {
    id: label
    anchors.centerIn: parent
    color: VistaScheme.infoText
    font.family: "Tahoma"
    font.pixelSize: Style.font.bodySmall
  }
}
