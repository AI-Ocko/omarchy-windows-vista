import QtQuick

// VistaEtched: SS_ETCHEDHORZ / SS_ETCHEDVERT -- a 1 px Btnshadow line with a
// 1 px Btnhighlight line beside it. Set `vertical` for a vertical rule.
Item {
  property bool vertical: false
  implicitWidth: vertical ? 2 : 0
  implicitHeight: vertical ? 0 : 2

  Rectangle {
    width: parent.vertical ? 1 : parent.width
    height: parent.vertical ? parent.height : 1
    color: "#ACA899"
  }
  Rectangle {
    x: parent.vertical ? 1 : 0
    y: parent.vertical ? 0 : 1
    width: parent.vertical ? 1 : parent.width
    height: parent.vertical ? parent.height : 1
    color: "#FFFFFF"
  }
}
