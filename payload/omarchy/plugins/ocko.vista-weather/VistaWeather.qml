import QtQuick
import qs.Commons
import "../../vista/qml"

// The Vista card of ocko.vista-weather: a one-page property sheet ("Weather",
// General) with Location, Current conditions and Forecast group boxes, over
// the stock weather panel's state. Vista had no weather applet, so the layout
// follows the property-page grid every Vista sheet uses (252 DLU wide, 7 DLU
// margins, Tahoma 8). `host` is the panel (Panel.qml) or, for the screenshot
// harness, a mock with the same members; nothing here fetches anything.
//
// host reads:  label, current, reportLocation, configuredLocation,
//   reportTempNum, tempUnit, reportFeels, reportWind, reportHumidity,
//   forecastDays, editingLocation, savingLocation, locationSuggestions,
//   suggestionIndex (written by the arrow keys)
// host calls: startEditingLocation, cancelEditingLocation, commitLocation,
//   clearLocation, pickSuggestion, vistaLocationEdited, dayIcon, dayName,
//   bareTempForDay, refresh, close
VistaPropertySheet {
  id: wv

  required property var host
  // The edit box's TextInput; stock reads it as `locationField`.
  readonly property alias locationInput: locField.input

  readonly property var days: host.forecastDays || []
  readonly property bool hasForecast: days.length > 0
  readonly property var suggestions: host.locationSuggestions || []

  function s(n) { return Style.space(n) }
  function du(x) { return Style.space(Math.round(x * 1.5)) }
  function dv(y) { return Style.space(Math.round(y * 13 / 8)) }

  // Stock weather glyph -> the Vista art Bar.qml's vistaTrayArt gives the tray
  // icon (phase 1): stars for clear skies, netshell's Internet cloud with its
  // bolt for storms, the cloud cropped of plug and bolt for the rest. Only
  // the 32 px export exists for 1111/1111-cloud.
  function artUrl(glyph) {
    var c = String(glyph || "").charCodeAt(0)
    if (!c) return ""
    var art = c === 0xE30D ? "shell32/44"        // clear, day
            : c === 0xE32B ? "shell32/173"       // clear, night
            : c === 0xE31D ? "netshell/1111"     // thunderstorm
            : "netshell/1111-cloud"
    var slash = art.indexOf("/")
    return VistaScheme.graphics + "/" + art.slice(0, slash) + "/32" + art.slice(slash) + ".png"
  }

  function fieldKey(e) {
    if (e.key === Qt.Key_Escape) wv.host.cancelEditingLocation()
    else if (e.key === Qt.Key_Down) { if (wv.host.suggestionIndex < wv.suggestions.length - 1) wv.host.suggestionIndex++ }
    else if (e.key === Qt.Key_Up) { if (wv.host.suggestionIndex > 0) wv.host.suggestionIndex-- }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) wv.host.commitLocation()
    else return
    e.accepted = true
  }

  title: "Weather"
  titleIcon: artUrl(host.label)
  buttons: ["close"]
  onCloseClicked: host.close()
  titles: ["General"]
  pageWidth: du(252)
  pageHeight: dv(hasForecast ? 180 : 110)
  // Refresh is the bar button's middle click.
  buttonLabels: ["<u>R</u>efresh", "Close"]
  defaultButton: 1
  onButtonClicked: function(i) { if (i === 0) host.refresh(); else host.close() }

  Item {
    parent: wv.page
    anchors.fill: parent

    // ---- Location -----------------------------------------------------
    VistaGroupBox { x: wv.du(7); y: wv.dv(7); width: wv.du(238); height: wv.dv(34); caption: "Location" }

    VistaLabel {
      x: wv.du(14); y: wv.dv(21)
      visible: !wv.host.editingLocation
      text: "Location:"
    }
    Row {
      x: wv.du(52); y: wv.dv(21)
      width: wv.du(132)
      visible: !wv.host.editingLocation
      spacing: wv.s(4)
      VistaLabel {
        id: locName
        width: Math.min(implicitWidth, parent.width - (autoTag.visible ? autoTag.implicitWidth + parent.spacing : 0))
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: wv.host.reportLocation || "Detecting..."
        // Stock: clicking the location label edits it.
        TapHandler { onTapped: wv.host.startEditingLocation() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
      }
      VistaLabel {
        id: autoTag
        visible: wv.host.configuredLocation === ""
        enabled: false
        text: "(automatic)"
      }
    }

    VistaTextField {
      id: locField
      x: wv.du(14); y: wv.dv(19)
      width: wv.du(168); height: wv.dv(13)
      visible: wv.host.editingLocation
      enabled: !wv.host.savingLocation
      placeholder: "Search city"
      onTextChanged: wv.host.vistaLocationEdited()
      input.Keys.onPressed: function(e) { wv.fieldKey(e) }
    }

    VistaButton {
      x: wv.du(188); y: wv.dv(18)
      width: wv.du(50); height: wv.dv(14)
      visible: !wv.host.editingLocation
      text: "<u>C</u>hange..."
      onClicked: wv.host.startEditingLocation()
    }
    // Stock's clear button: back to IP auto-detect; its spinner while a new
    // location loads is this button's "Saving..." state.
    VistaButton {
      x: wv.du(188); y: wv.dv(18)
      width: wv.du(50); height: wv.dv(14)
      visible: wv.host.editingLocation
      enabled: !wv.host.savingLocation
      text: wv.host.savingLocation ? "Saving..." : "<u>A</u>utomatic"
      onClicked: wv.host.clearLocation()
    }

    // ---- Current conditions -------------------------------------------
    VistaGroupBox { x: wv.du(7); y: wv.dv(47); width: wv.du(238); height: wv.dv(56); caption: "Current conditions" }

    Row {
      x: wv.du(14); y: wv.dv(62)
      spacing: wv.s(10)
      Image {
        anchors.verticalCenter: parent.verticalCenter
        width: wv.s(24); height: wv.s(24)
        sourceSize: Qt.size(width, height)
        source: wv.artUrl(wv.host.label)
        visible: source.toString() !== ""
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: wv.s(2)
        Text {
          id: tempBig
          textFormat: Text.PlainText
          text: wv.host.reportTempNum || "—"
          color: "#000000"
          font.family: "Segoe UI"
          font.pixelSize: Style.font.display
          font.bold: true
        }
        Text {
          y: wv.s(3)
          textFormat: Text.PlainText
          text: wv.host.current ? wv.host.tempUnit : ""
          color: "#000000"
          font.family: "Segoe UI"
          font.pixelSize: Style.font.heading
        }
      }
    }

    VistaLabel {
      x: wv.du(132); y: wv.dv(62)
      visible: !wv.host.current
      font.italic: true
      text: "Fetching forecast..."
    }
    Repeater {
      model: wv.host.current ? 3 : 0
      Item {
        required property int index
        x: wv.du(132); y: wv.dv(62 + 12 * index)
        width: wv.du(106); height: wv.dv(10)
        VistaLabel { text: ["Feels like:", "Wind:", "Humidity:"][parent.index] }
        VistaLabel {
          x: wv.du(44)
          textFormat: Text.PlainText
          text: [wv.host.reportFeels, wv.host.reportWind, wv.host.reportHumidity][parent.index]
        }
      }
    }

    // ---- Forecast -----------------------------------------------------
    VistaGroupBox {
      visible: wv.hasForecast
      x: wv.du(7); y: wv.dv(109); width: wv.du(238); height: wv.dv(64)
      caption: "Forecast"
    }
    Row {
      visible: wv.hasForecast
      x: wv.du(12); y: wv.dv(123)
      Repeater {
        model: wv.days.length
        Column {
          required property int index
          readonly property var day: wv.days[index]
          width: wv.du(76)
          spacing: wv.s(4)
          VistaLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            font.bold: true
            text: wv.host.dayName(parent.day.date)
          }
          Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: wv.s(24); height: wv.s(24)
            sourceSize: Qt.size(width, height)
            source: wv.artUrl(wv.host.dayIcon(parent.day))
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: wv.s(6)
            VistaLabel { textFormat: Text.PlainText; text: wv.host.bareTempForDay(parent.parent.day, "max") }
            VistaLabel { textFormat: Text.PlainText; enabled: false; text: wv.host.bareTempForDay(parent.parent.day, "min") }
          }
        }
      }
    }

    // ---- Geocoding suggestions: an autocomplete drop-down under the edit
    // box, over the groups below it.
    VistaListView {
      z: 10
      visible: wv.host.editingLocation && !wv.host.savingLocation && wv.suggestions.length > 0
      x: wv.du(14); y: wv.dv(32)
      width: wv.du(168)
      height: wv.suggestions.length * rowHeight + 2
      focused: true
      rows: wv.suggestions.map(function(sg) { return [sg.description ? sg.name + ", " + sg.description : sg.name] })
      currentIndex: wv.host.suggestionIndex
      onClicked: function(i) { wv.host.pickSuggestion(wv.suggestions[i]) }
    }
  }
}
