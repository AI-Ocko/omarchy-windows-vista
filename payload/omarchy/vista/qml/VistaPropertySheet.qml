import QtQuick
import qs.Commons

// VistaPropertySheet: an Vista property sheet -- VistaWindow chrome, an VistaTabs
// control inset 6 px, and the push buttons along the bottom right (OK,
// Cancel, Apply, or a lone Close). Sized from its page. A page attaches with
// `parent: <sheet>.page` and shows for its tab by binding `visible`.
VistaWindow {
  id: sheet

  property var titles: []
  property int tab: 0
  property real pageWidth: 0
  property real pageHeight: 0
  // Labels, left to right; indices in disabledButtonIndices draw disabled.
  property var buttonLabels: []
  property var disabledButtonIndices: []
  property int defaultButton: 0
  readonly property Item page: sheetTabs.page
  signal buttonClicked(int index)
  signal tabClicked(int index)

  width: pageWidth + Style.space(4 + 12) + 2 * frameWidth
  height: captionHeight + Style.space(6) + sheetTabs.tabHeight + pageHeight + Style.space(4) + Style.space(6 + 23 + 6) + frameWidth

  VistaTabs {
    id: sheetTabs
    x: Style.space(6)
    y: Style.space(6)
    width: sheet.pageWidth + Style.space(4)
    height: tabHeight + sheet.pageHeight + Style.space(4)
    titles: sheet.titles
    currentIndex: sheet.tab
    onActivated: function(i) { sheet.tabClicked(i) }
  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(6)
    spacing: Style.space(6)
    Repeater {
      model: sheet.buttonLabels
      VistaButton {
        required property int index
        required property var modelData
        text: String(modelData)
        isDefault: index === sheet.defaultButton
        enabled: sheet.disabledButtonIndices.indexOf(index) === -1
        onClicked: sheet.buttonClicked(index)
      }
    }
  }
}
