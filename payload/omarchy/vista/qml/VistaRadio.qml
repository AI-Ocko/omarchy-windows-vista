import QtQuick
import qs.Commons

// VistaRadio: [Button.RadioButton], the 96-dpi RadioButton13 bitmap: 8 frames,
// unchecked then checked x normal, hot, pressed, disabled. Tahoma 8 label,
// Vista's focus rectangle round it when `focused`. Emits clicked(); the owner
// sets `checked`.
Item {
  id: rb

  property string artDir: VistaScheme.artDir
  property string text: ""
  property bool checked: false
  property bool focused: false
  signal clicked()

  implicitWidth: box.width + (text ? Style.space(5) + label.implicitWidth + Style.space(2) : 0)
  implicitHeight: Math.max(box.height, label.implicitHeight)

  Image {
    id: box
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(13)
    height: Style.space(13)
    source: rb.artDir + "/radio-" + ((rb.checked ? 4 : 0) + (!rb.enabled ? 3 : mouse.pressed ? 2 : mouse.containsMouse ? 1 : 0)) + ".png"
    smooth: true
  }

  VistaLabel {
    id: label
    anchors.left: box.right
    anchors.leftMargin: Style.space(5)
    anchors.verticalCenter: parent.verticalCenter
    text: rb.text
    enabled: rb.enabled
  }

  Rectangle {
    visible: rb.focused && rb.text !== ""
    x: label.x - Style.space(1)
    y: label.y
    width: label.implicitWidth + Style.space(2)
    height: label.implicitHeight
    color: "transparent"
    border.width: 1
    border.color: "#000000"
    opacity: 0.45
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: rb.enabled
    onClicked: rb.clicked()
  }
}
