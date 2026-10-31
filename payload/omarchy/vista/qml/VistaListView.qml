import QtQuick
import qs.Commons

// VistaListView: [ListView] in report view: white with a 1 px 127 157 185
// border, a [Header.HeaderItem] strip (ListViewHeader, 5 frames: normal,
// hot, pressed, ...; SizingMargins 8, 8, 3, 4) and Tahoma 8 rows. The
// selection is the scheme's Highlight while `focused`, else button face, as
// Vista shows an unfocused selection. columns: [{ title, width }] in 96-dpi px,
// the last one stretching; rows: arrays of cell strings, or { group: "…" }
// for a comctl32 v6 group header (bold, with a rule to the right). An
// optional `leading` component draws in front of each row's first cell (an
// icon, say); it reads `rowIndex` from its parent.
Rectangle {
  id: lv

  property string artDir: VistaScheme.artDir
  property var columns: []
  property var rows: []
  property int currentIndex: -1
  property bool focused: false
  property Component leading: null
  readonly property alias contentY: list.contentY
  signal clicked(int index)
  signal activated(int index)

  readonly property real headerHeight: Style.space(18)
  readonly property real rowHeight: Style.space(16)
  function colWidth(i) {
    if (i < columns.length - 1) return Style.space(columns[i].width || 80)
    var used = 0
    for (var j = 0; j < columns.length - 1; j++) used += Style.space(columns[j].width || 80)
    return Math.max(Style.space(columns[i].width || 40), lv.width - 2 - used)
  }

  implicitWidth: Style.space(300)
  implicitHeight: Style.space(160)
  color: "#FFFFFF"
  border.width: 1
  border.color: "#7F9DB9"
  clip: true

  Row {
    id: header
    x: 1
    y: 1
    visible: lv.columns.length > 0
    Repeater {
      model: lv.columns.length
      Item {
        required property int index
        width: lv.colWidth(index)
        height: lv.headerHeight
        VistaArt {
          anchors.fill: parent
          source: lv.artDir + "/header-" + (hMouse.pressed ? 2 : hMouse.containsMouse ? 1 : 0) + ".png"
          margins: [8, 8, 3, 4]
        }
        Text {
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          text: String(lv.columns[parent.index].title || "")
          font.family: "Segoe UI"
          font.pixelSize: Style.font.bodySmall
        }
        MouseArea { id: hMouse; anchors.fill: parent; hoverEnabled: true }
      }
    }
  }

  ListView {
    id: list
    x: 1
    y: header.visible ? lv.headerHeight + 1 : 1
    width: lv.width - 2
    height: lv.height - y - 1
    clip: true
    model: lv.rows.length
    currentIndex: lv.currentIndex
    boundsBehavior: Flickable.StopAtBounds
    delegate: Item {
      id: row
      required property int index
      readonly property bool selected: index === lv.currentIndex
      readonly property var group: { var r = lv.rows[index]; return r && !Array.isArray(r) && r.group !== undefined ? String(r.group) : null }
      width: list.width
      height: lv.rowHeight
      // Group header: Luna's blue bold caption and a 1 px rule after it
      // (colour from memory, not from the msstyles).
      Text {
        id: groupText
        visible: row.group !== null
        x: Style.space(4)
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: row.group || ""
        color: "#215DC6"
        font.family: "Segoe UI"
        font.bold: true
        font.pixelSize: Style.font.bodySmall
      }
      Rectangle {
        visible: row.group !== null
        x: groupText.x + groupText.implicitWidth + Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - x - Style.space(4))
        height: 1
        color: "#215DC6"
      }
      Row {
        visible: row.group === null
        Repeater {
          model: Math.max(1, lv.columns.length)
          Item {
            required property int index
            width: lv.columns.length ? lv.colWidth(index) : list.width
            height: lv.rowHeight
            readonly property real lead: index === 0 && lv.leading ? Style.space(20) : 0
            Loader {
              active: parent.index === 0 && lv.leading !== null && row.group === null
              x: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(16)
              height: Style.space(16)
              property int rowIndex: row.index
              sourceComponent: lv.leading
            }
            Rectangle {
              // Vista highlights the first column's text only.
              visible: row.selected && parent.index === 0
              x: Style.space(2) + parent.lead
              width: Math.min(parent.width - parent.lead - Style.space(4), cell.implicitWidth + Style.space(4))
              height: parent.height
              color: lv.focused ? VistaScheme.sc.highlight : VistaScheme.sc.face
            }
            Text {
              id: cell
              anchors.fill: parent
              anchors.leftMargin: Style.space(4) + parent.lead
              anchors.rightMargin: Style.space(4)
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
              text: { var r = lv.rows[row.index]; if (!Array.isArray(r)) return ""; return String(r[parent.index] === undefined ? "" : r[parent.index]) }
              color: row.selected && parent.index === 0 && lv.focused ? VistaScheme.sc.highlightText : "#000000"
              font.family: "Segoe UI"
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        enabled: row.group === null
        onClicked: lv.clicked(row.index)
        onDoubleClicked: lv.activated(row.index)
      }
    }
  }
}
