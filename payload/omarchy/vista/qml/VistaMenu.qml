import QtQuick
import qs.Commons

// VistaMenu: the body of an Vista context menu. Luna menus are not bitmap-skinned:
// the Menu face is white, the edge a 1 px Btnshadow (#ACA899) with the
// drop shadow Vista draws on the right and bottom, the hot item the scheme's
// Highlight with HighlightText, disabled text GrayText. Tahoma 8 items,
// a check gutter on the left and a submenu arrow on the right.
// items: [{ text, checked, radio, icon, enabled, separator, submenu, bold }];
// a checked radio item draws Vista's bullet, an icon (url) sits in the check
// gutter when the item is not checked. rowY(i) is item i's top, for
// anchoring a cascaded submenu beside it. The host
// puts it in its popup surface and handles triggered(index); for keys it
// calls moveBy(+1/-1) and activateCurrent().
Item {
  id: menu

  property var items: []
  property int currentIndex: -1
  signal triggered(int index)

  readonly property real itemHeight: Style.space(17)
  readonly property real sepHeight: Style.space(9)
  readonly property real gutter: Style.space(18)
  readonly property real shadow: Style.space(2)

  function selectable(i) {
    var it = items[i]
    return !!it && !it.separator && it.enabled !== false
  }
  function moveBy(d) {
    for (var n = 0, i = currentIndex; n < items.length; n++) {
      i = (i + d + items.length) % items.length
      if (selectable(i)) { currentIndex = i; return }
    }
  }
  function activateCurrent() { if (selectable(currentIndex)) triggered(currentIndex) }
  function rowY(i) {
    var y = 1 + Style.space(2)
    for (var j = 0; j < i && j < items.length; j++) y += items[j] && items[j].separator ? sepHeight : itemHeight
    return y
  }

  implicitWidth: Math.max(Style.space(120), column.widest + 2 * gutter + 2) + shadow
  implicitHeight: column.height + 2 + Style.space(4) + shadow

  // Drop shadow (Vista's menu shadow is a soft 4 px; this is its 2 px core).
  Rectangle {
    x: menu.shadow
    y: menu.shadow
    width: parent.width - menu.shadow
    height: parent.height - menu.shadow
    color: "#000000"
    opacity: 0.22
  }

  Rectangle {
    width: parent.width - menu.shadow
    height: parent.height - menu.shadow
    color: "#FFFFFF"
    border.width: 1
    border.color: "#ACA899"

    Column {
      id: column
      x: 1
      y: 1 + Style.space(2)
      width: parent.width - 2
      property real widest: 0

      Repeater {
        model: menu.items.length
        Item {
          id: entry
          required property int index
          readonly property var item: menu.items[index] || {}
          readonly property bool sep: item.separator === true
          readonly property bool lit: !sep && menu.currentIndex === index && item.enabled !== false
          width: column.width
          height: sep ? menu.sepHeight : menu.itemHeight

          Rectangle {
            visible: entry.sep
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(1)
            width: parent.width - Style.space(2)
            height: 1
            color: "#ACA899"
          }

          Rectangle {
            visible: entry.lit
            anchors.fill: parent
            color: VistaScheme.sc.highlight
          }

          Text {
            visible: !entry.sep && entry.item.checked === true
            width: menu.gutter
            height: parent.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            // Marlett's check, or its bullet for a radio item.
            text: entry.item.radio === true ? "\u25CF" : "✓"
            color: label.color
            font.family: "Segoe UI"
            font.pixelSize: Style.font.bodySmall
          }

          Image {
            visible: !entry.sep && entry.item.checked !== true && String(entry.item.icon || "") !== ""
            x: (menu.gutter - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: Style.space(16)
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
            opacity: entry.item.enabled === false ? 0.5 : 1
            source: visible ? entry.item.icon : ""
          }

          Text {
            id: label
            visible: !entry.sep
            x: menu.gutter
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: String(entry.item.text || "")
            textFormat: Text.StyledText
            color: entry.item.enabled === false ? "#ACA899" : entry.lit ? VistaScheme.sc.highlightText : "#000000"
            font.family: "Segoe UI"
            font.bold: entry.item.bold === true
            font.pixelSize: Style.font.bodySmall
            onImplicitWidthChanged: if (implicitWidth > column.widest) column.widest = implicitWidth
          }

          // Submenu arrow: a 4 x 7 px solid triangle, as Vista's Marlett glyph.
          Item {
            visible: !entry.sep && entry.item.submenu === true
            anchors.right: parent.right
            anchors.rightMargin: Style.space(7)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(4)
            height: Style.space(7)
            clip: true
            Rectangle {
              width: parent.height / Math.SQRT2
              height: width
              x: -width / 2
              y: (parent.height - height) / 2
              rotation: 45
              color: label.color
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: !entry.sep
            onContainsMouseChanged: if (containsMouse) menu.currentIndex = entry.item.enabled === false ? -1 : entry.index
            onClicked: if (menu.selectable(entry.index)) menu.triggered(entry.index)
          }
        }
      }
    }
  }
}
