import QtQuick
import qs.Commons

// VistaCheckBox: [Button.CheckBox] of the active scheme, the 96-dpi CheckBox13
// bitmap: 12 frames, unchecked / checked / mixed x normal, hot, pressed,
// disabled. Tahoma 8, disabled text 161 161 146, Vista's dotted focus rectangle
// round the label when `focused`. Emits toggled(); the owner flips `checked`.
Item {
  id: cb

  property string artDir: VistaScheme.artDir
  property string text: ""
  property bool checked: false
  property bool mixed: false
  property bool focused: false
  signal toggled()

  implicitWidth: box.width + (text ? Style.space(5) + label.implicitWidth + Style.space(2) : 0)
  implicitHeight: Math.max(box.height, label.implicitHeight)

  Image {
    id: box
    readonly property int frame: (cb.mixed ? 8 : cb.checked ? 4 : 0)
                                 + (!cb.enabled ? 3 : mouse.pressed ? 2 : mouse.containsMouse ? 1 : 0)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(13)
    height: Style.space(13)
    source: cb.artDir + "/check-" + frame + ".png"
    smooth: true
  }

  Text {
    id: label
    anchors.left: box.right
    anchors.leftMargin: Style.space(5)
    anchors.verticalCenter: parent.verticalCenter
    text: cb.text
    textFormat: Text.StyledText
    color: cb.enabled ? "#000000" : "#A1A192"
    font.family: "Tahoma"
    font.pixelSize: Style.font.bodySmall
  }

  Rectangle {
    visible: cb.focused && cb.text !== ""
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
    enabled: cb.enabled
    onClicked: cb.toggled()
  }
}
