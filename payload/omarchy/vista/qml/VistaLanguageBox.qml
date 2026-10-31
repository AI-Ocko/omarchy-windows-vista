import QtQuick
import qs.Commons

// Vista's notification-area language indicator: the active input language's
// short code ("EN", "DE") in white Tahoma Bold on a blue tile. Vista drew it at
// runtime (msctf.dll and input.dll carry no bitmap for it) and always in
// Luna's Highlight blue (palette.md), whatever the colour scheme. Holds no
// MouseArea, so clicks and hover fall through to the widget underneath.
Rectangle {
  id: box

  property string code: ""

  implicitWidth: Math.max(Style.space(16), label.implicitWidth + Style.space(4))
  implicitHeight: Style.space(16)
  radius: Style.space(2)
  color: "#316AC5"

  Text {
    id: label
    anchors.centerIn: parent
    text: box.code.toUpperCase()
    color: "#FFFFFF"
    font.family: "Tahoma"
    font.bold: true
    font.pixelSize: Style.font.caption
  }
}
