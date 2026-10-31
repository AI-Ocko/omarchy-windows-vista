import QtQuick
import Quickshell
import qs.Commons
import "../../vista/qml"

// The Vista card of ocko.vista-weather: a one-page property sheet ("Weather",
// General) with Location, Current conditions and Forecast group boxes, over
// the stock weather panel's state. Vista had no weather applet; its weather
// was the Sidebar's Weather gadget, so Current conditions is that gadget's
// large view (assets/gadgets/Weather.Gadget) and the forecast uses its icons,
// on the property-page grid every Vista sheet uses (252 DLU wide, 7 DLU
// margins, 8 pt). `host` is the panel (Panel.qml) or, for the screenshot
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
  // The condition code now: wttr.in's (weatherCode) or Open-Meteo's.
  readonly property var currentCode: host.current ? (host.current.weatherCode !== undefined ? { wttr: Number(host.current.weatherCode) }
    : { wmo: Number(host.current.openMeteoWeatherCode) }) : null
  // -> the gadget's undocked_<kind>.png
  function kindOf(code) {
    if (!code) return "cloudy"
    if (code.wmo !== undefined) {
      var w = code.wmo
      return w === 0 ? "sun" : w <= 2 ? "partly-cloudy" : w === 3 ? "cloudy" : w === 45 || w === 48 ? "foggy"
        : w >= 95 ? "thunderstorm" : (w >= 71 && w <= 77) || w === 85 || w === 86 ? "snow"
        : w >= 80 ? "few-showers" : w >= 51 && w <= 57 ? "few-showers" : w >= 61 ? "rainy" : "cloudy"
    }
    var c = code.wttr
    if (c === 113) return "sun"
    if (c === 116) return "partly-cloudy"
    if (c === 119 || c === 122) return "cloudy"
    if ([143, 248, 260].indexOf(c) !== -1) return "foggy"
    if ([200, 386, 389, 392, 395].indexOf(c) !== -1) return "thunderstorm"
    if ([350, 374, 377].indexOf(c) !== -1) return "hail"
    if ([179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371].indexOf(c) !== -1) return "snow"
    if ([176, 263, 266, 293, 296, 353].indexOf(c) !== -1) return "few-showers"
    return c >= 281 ? "rainy" : "cloudy"
  }
  // Open-Meteo (WMO) code -> the gadget's numbered forecast icon (the
  // AccuWeather set it used: 1 sunny, 3 partly sunny, 7 cloudy, 11 fog,
  // 12 showers, 15 thunderstorms, 18 rain, 22 snow, 26 freezing rain).
  function accuOf(wmo, day) {
    var w = Number(wmo)
    if (isNaN(w)) return 7
    return w === 0 ? 1 : w === 1 ? 2 : w === 2 ? 3 : w === 3 ? 7 : w === 45 || w === 48 ? 11
      : w >= 95 ? 15 : w === 56 || w === 57 || w === 66 || w === 67 ? 26 : (w >= 71 && w <= 77) || w === 85 || w === 86 ? 22
      : w >= 80 || (w >= 51 && w <= 55) ? 12 : w >= 61 ? 18 : 7
  }
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
  pageHeight: dv(hasForecast ? 266 : 196)
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

    // ---- Current conditions: the Weather gadget's large (undocked) view:
    // BLUE-base (264 x 194) with the condition's undocked art, the
    // temperature and the place, then the details on one line.
    VistaGroupBox { x: wv.du(7); y: wv.dv(47); width: wv.du(238); height: wv.dv(142); caption: "Current conditions" }
    Item {
      id: gadget
      x: wv.du(7) + (wv.du(238) - width) / 2; y: wv.dv(60)
      width: wv.s(264); height: wv.s(194)
      readonly property string g: "file://" + Quickshell.env("HOME") + "/.config/omarchy/vista/assets/gadgets/Weather.Gadget/images/"
      Image { anchors.fill: parent; source: gadget.g + "BLUE-base.png"; smooth: true }
      Image {
        anchors.fill: parent
        source: gadget.g + (wv.host.current ? "undocked_" + wv.kindOf(wv.currentCode) + ".png" : "undocked-loading.png")
        smooth: true
      }
      Text {
        anchors.right: parent.right; anchors.rightMargin: wv.s(18)
        y: wv.s(14)
        textFormat: Text.PlainText
        text: wv.host.current ? (wv.host.reportTempNum || "") + "°" : ""
        color: "white"
        font.family: "Segoe UI"
        font.pixelSize: wv.s(44)
        style: Text.Raised; styleColor: "#50000000"
      }
      Text {
        anchors.right: parent.right; anchors.rightMargin: wv.s(18)
        anchors.bottom: parent.bottom; anchors.bottomMargin: wv.s(18)
        width: parent.width - wv.s(36)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: wv.host.reportLocation || wv.host.configuredLocation || ""
        color: "white"
        font.family: "Segoe UI"
        font.pixelSize: wv.s(13)
      }
    }
    VistaLabel {
      x: wv.du(14); y: wv.dv(60) + gadget.height + wv.s(6)
      width: wv.du(224)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      font.italic: !wv.host.current
      text: !wv.host.current ? "Fetching forecast..."
        : "Feels like " + wv.host.reportFeels + "   ·   Wind " + wv.host.reportWind + "   ·   Humidity " + wv.host.reportHumidity
    }

    // ---- Forecast -----------------------------------------------------
    VistaGroupBox {
      visible: wv.hasForecast
      x: wv.du(7); y: wv.dv(195); width: wv.du(238); height: wv.dv(64)
      caption: "Forecast"
    }
    Row {
      visible: wv.hasForecast
      x: wv.du(12); y: wv.dv(209)
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
            width: wv.s(42); height: wv.s(34)
            source: gadget.g + wv.accuOf(parent.day.openMeteoWeatherCode, true) + ".png"
            smooth: true
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
