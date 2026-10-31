import QtQuick
import qs.Commons

// VistaLabel: a dialog static -- Tahoma 8 in WindowText, GrayText (as the
// Luna dialogs draw it, #ACA899) when disabled.
Text {
  color: enabled ? "#000000" : "#ACA899"
  textFormat: Text.StyledText
  font.family: "Segoe UI"
  font.pixelSize: Style.font.bodySmall
}
