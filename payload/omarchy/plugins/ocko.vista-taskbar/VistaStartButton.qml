import QtQuick
import QtQuick.Window
import qs.Commons

// The Windows Vista Start orb: aero.msstyles StartBottom::Button, three frames
// (normal, hot, pressed) at 96/120/144/192 dpi (assets/graphics/taskbar/orb/
// <dpi>/<frame>.png, from bin/vista-art). Drawn at its 96-dpi size, 60 x 46,
// from the variant nearest above the screen's real density so it stays sharp.
// The circle is 42 x 40 at +9,+4 in the frame; `hit` is that circle, which the
// bar's input mask uses where the orb overhangs the taskbar.
Item {
  id: start

  required property string orbRoot
  property bool menuOpen: false
  signal activated()
  readonly property alias hit: hitArea

  implicitWidth: Style.space(60)
  implicitHeight: Style.space(46)
  width: implicitWidth
  height: implicitHeight

  readonly property real density: Style.spaceReal(1) * Screen.devicePixelRatio
  readonly property int dpi: density <= 1 ? 96 : density <= 1.25 ? 120 : density <= 1.5 ? 144 : 192

  Image {
    anchors.fill: parent
    source: start.orbRoot + "/" + start.dpi + "/" + (start.menuOpen || mouse.pressed ? 2 : mouse.containsMouse ? 1 : 0) + ".png"
    smooth: true
    mipmap: true
  }

  Item {
    id: hitArea
    x: Style.space(9)
    y: Style.space(4)
    width: Style.space(42)
    height: Style.space(40)

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: start.activated()
    }
  }
}
