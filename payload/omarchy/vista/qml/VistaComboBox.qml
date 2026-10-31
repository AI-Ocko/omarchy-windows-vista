import QtQuick
import qs.Commons

// VistaComboBox: a drop-down list ([Combobox], CBS_DROPDOWNLIST): a white field
// with a 1 px 127 157 185 border, [Combobox.DropDownButton] (4 frames:
// normal, hot, pressed, disabled; SizingMargins 3) and its glyph. The list
// opens below, inside the owner's window like the Run dialog's history, so
// give the combo a z above its siblings. Emits activated(index); the owner
// sets currentIndex.
Item {
  id: combo

  property string artDir: VistaScheme.artDir
  property var model: []
  property int currentIndex: -1
  property bool open: false
  property bool focused: false
  property int visibleRows: 8
  signal activated(int index)

  readonly property real rowHeight: Style.space(15)

  implicitWidth: Style.space(150)
  implicitHeight: Style.space(21)

  Rectangle {
    id: field
    anchors.fill: parent
    color: combo.enabled ? "#FFFFFF" : "#F5F4EA"
    border.width: 1
    border.color: combo.enabled ? "#7F9DB9" : "#C9C7BA"

    // Selected text, highlighted while focused as Vista draws it.
    Rectangle {
      anchors.left: parent.left
      anchors.right: button.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(3)
      color: combo.focused && !combo.open ? VistaScheme.sc.highlight : "transparent"

      Text {
        anchors.fill: parent
        anchors.leftMargin: Style.space(2)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: combo.currentIndex >= 0 && combo.currentIndex < combo.model.length ? String(combo.model[combo.currentIndex]) : ""
        color: !combo.enabled ? "#A1A192" : combo.focused && !combo.open ? VistaScheme.sc.highlightText : "#000000"
        font.family: "Tahoma"
        font.pixelSize: Style.font.bodySmall
      }
    }

    Item {
      id: button
      anchors.right: parent.right
      anchors.rightMargin: 1
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(17)
      height: parent.height - 2
      readonly property int frame: !combo.enabled ? 3 : (fieldMouse.pressed || combo.open) ? 2 : fieldMouse.containsMouse ? 1 : 0
      VistaArt {
        anchors.fill: parent
        source: combo.artDir + "/combo-" + button.frame + ".png"
        margins: [3, 3, 3, 3]
      }
      Image {
        anchors.centerIn: parent
        width: Style.space(10)
        height: Style.space(7)
        source: combo.artDir + "/combog-" + button.frame + ".png"
        smooth: true
      }
    }

    MouseArea {
      id: fieldMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: combo.enabled
      onClicked: combo.open = !combo.open
    }
  }

  // Drop list: black 1 px border, the scheme's Highlight under the pointer.
  Rectangle {
    visible: combo.open
    y: combo.height
    width: combo.width
    height: Math.min(combo.model.length, combo.visibleRows) * combo.rowHeight + 2
    color: "#FFFFFF"
    border.width: 1
    border.color: "#000000"

    ListView {
      id: list
      anchors.fill: parent
      anchors.margins: 1
      clip: true
      model: combo.model.length
      currentIndex: combo.currentIndex
      delegate: Rectangle {
        required property int index
        width: list.width
        height: combo.rowHeight
        // Vista lights the row under the pointer, else the current one.
        readonly property bool lit: list.hoveredIndex >= 0 ? index === list.hoveredIndex : index === list.currentIndex
        color: lit ? VistaScheme.sc.highlight : "transparent"
        Text {
          anchors.fill: parent
          anchors.leftMargin: Style.space(2)
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          text: String(combo.model[parent.index])
          color: parent.lit ? VistaScheme.sc.highlightText : "#000000"
          font.family: "Tahoma"
          font.pixelSize: Style.font.bodySmall
        }
        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          onContainsMouseChanged: if (containsMouse) list.hoveredIndex = parent.index
                                  else if (list.hoveredIndex === parent.index) list.hoveredIndex = -1
          onClicked: { combo.open = false; combo.activated(parent.index) }
        }
      }
      property int hoveredIndex: -1
      Component.onCompleted: positionViewAtIndex(Math.max(0, combo.currentIndex), ListView.Contain)
    }
  }
}
