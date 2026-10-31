import QtQuick
import qs.Commons

// VistaTextField: an Vista edit box ([edit] BgType BorderFill: white, 1 px border in
// the scheme's BorderColor; ReadOnly/Disabled fill 235 235 228), Tahoma 8,
// selection in the scheme's Highlight. `input` is the TextInput, for focus,
// echoMode and key handling by the owner. interactive: false makes it a
// display (the owner's key handler types into `text`) with the caret parked
// at the end and shown while `caret` is true.
Rectangle {
  id: field

  property alias text: input.text
  property alias input: input
  property alias echoMode: input.echoMode
  property bool readOnly: false
  property string placeholder: ""
  property bool interactive: true
  property bool caret: false

  implicitWidth: Style.space(200)
  implicitHeight: Style.space(21)
  color: readOnly || !enabled ? "#EBEBE4" : "#FFFFFF"
  border.width: Math.max(1, Style.space(1))
  border.color: VistaScheme.sc.edit

  TextInput {
    id: input
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(3)
    anchors.rightMargin: Style.space(3)
    anchors.verticalCenter: parent.verticalCenter
    clip: true
    readOnly: field.readOnly || !field.interactive
    activeFocusOnPress: field.interactive
    cursorVisible: field.interactive ? activeFocus : field.caret
    onTextChanged: if (!field.interactive) cursorPosition = text.length
    selectByMouse: true
    passwordCharacter: "●"
    color: field.enabled ? "#000000" : VistaScheme.sc.gray
    selectionColor: VistaScheme.sc.highlight
    selectedTextColor: VistaScheme.sc.highlightText
    font.family: "Segoe UI"
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    visible: input.text.length === 0 && field.placeholder !== ""
    anchors.fill: input
    verticalAlignment: Text.AlignVCenter
    text: field.placeholder
    color: VistaScheme.sc.gray
    font: input.font
    elide: Text.ElideRight
  }

  MouseArea {
    anchors.fill: parent
    enabled: field.interactive
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.IBeamCursor
    onPressed: function(mouse) { input.forceActiveFocus(); mouse.accepted = false }
  }
}
