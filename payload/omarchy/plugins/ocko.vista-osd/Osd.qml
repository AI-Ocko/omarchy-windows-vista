import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "OsdModel.js" as OsdModel
import "../../vista/qml"

Item {
  id: root

  property bool opened: false
  property string icon: ""
  property string message: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200

  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0

  // The card is built out of measured columns instead of fixed widths, so it
  // keeps exactly `pad` between border and content on every side whatever
  // glyph or message it carries. Messages grow with their text up to
  // `maxMessageWidth` and elide beyond it.
  readonly property int pad: Style.space(16)
  readonly property int gap: Style.space(16)
  // A glyph next to a message reads airier than it measures: the icon outline
  // and the letterforms both fall away from their ink extremes, so the space
  // between them opens up well past the nominal gap. Text takes two thirds of
  // it; the progress bar's hard edge keeps the full gap.
  readonly property int messageGap: Math.round(root.gap * 2 / 3)
  readonly property int barWidth: Style.space(142)
  readonly property int maxMessageWidth: root.mediaOsd ? Style.space(325) : Style.space(190)

  // Nerd Font glyphs draw well outside their monospace cell, so the icon
  // column is measured by ink rather than by advance width. Progress OSDs pin
  // it to the widest glyph the model can return, so the bar doesn't shift when
  // volume crosses an icon threshold.
  readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
  readonly property int iconWidth: root.hasProgress
    ? Math.max(root.iconInkWidth, Math.ceil(widestIconMetrics.tightBoundingRect.width))
    : root.iconInkWidth
  // Same idea for the readout: it is as wide as the longest percentage so the
  // digits don't jitter between 9% and 100%.
  readonly property int valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, messageMetrics.advanceWidth))
  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  readonly property int contentWidth: root.hasProgress
    ? root.iconWidth + root.gap + root.barWidth + root.gap + root.valueWidth
    : (root.message === "" ? root.iconWidth : root.iconWidth + root.messageGap + root.messageWidth)

  function iconFor(name, percent) {
    return OsdModel.iconFor(name, percent)
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration)
    // Update before opening so a fresh OSD starts at its new value; only
    // subsequent updates while it remains open animate the progress bar.
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    opened = true
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration))
    } catch (e) {}
  }

  function close() { opened = false }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    text: root.message
  }

  TextMetrics {
    id: valueMetrics
    font: messageMetrics.font
    text: "100%"
  }

  TextMetrics {
    id: iconMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    text: root.icon
  }

  TextMetrics {
    id: widestIconMetrics
    font: iconMetrics.font
    text: OsdModel.widestIcon
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // ============================================================ Vista OSD
  // ocko.vista-osd: everything above is omarchy.osd 4.0.6 unchanged (payload
  // parsing, timers, IPC). The card is a small Vista tray popup above the
  // notification area: a raised Btnface panel with the shell32 Sounds or
  // Display icon, a Tahoma label, and the scheme's own progress bar
  // (Progress.Bar track + Progress.Chunk, 6 px chunks 2 px apart). Messages
  // without a value show as a plain Vista tooltip.
  property var shell: null
  readonly property int barClearance: shell && shell.bar && !shell.bar.barHidden && shell.bar.barSize > 0
    ? shell.bar.barSize : Style.space(30)
  readonly property string vistaLabel: {
    var k = root.iconKey
    if (k.indexOf("volume") === 0 || k === "mute" || k === "muted") return k.indexOf("mute") !== -1 ? "Volume (muted)" : "Volume"
    if (k.indexOf("mic") === 0) return k.indexOf("off") !== -1 || k.indexOf("mute") !== -1 ? "Microphone (muted)" : "Microphone"
    if (k === "brightness" || k === "display") return "Brightness"
    if (k === "keyboard") return "Keyboard"
    return ""
  }
  readonly property int vistaIcon: root.iconKey === "brightness" || root.iconKey === "display" ? 180 : 277

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only surface: keep the layer-shell input region empty so the OSD
    // never blocks clicks to the desktop below it.
    mask: Region {}

    function s(n) { return Style.space(n) }

    // Progress card: 1 px DkShadow3d edge around a 1 px white highlight, as
    // Vista's raised tray popups.
    Rectangle {
      id: card
      visible: root.hasProgress
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: panel.s(8)
      anchors.bottomMargin: root.barClearance + panel.s(4)
      width: panel.s(220)
      height: panel.s(58)
      color: "#716F64"
      Rectangle {
        anchors.fill: parent
        anchors.margins: Math.max(1, panel.s(1))
        color: "#FFFFFF"
        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: Math.max(1, panel.s(1))
          anchors.topMargin: Math.max(1, panel.s(1))
          color: VistaScheme.sc.face

          Image {
            id: osdIcon
            x: panel.s(10)
            anchors.verticalCenter: parent.verticalCenter
            width: panel.s(32)
            height: panel.s(32)
            source: VistaScheme.icon(root.vistaIcon, 32)
            smooth: true
          }
          Text {
            x: osdIcon.x + osdIcon.width + panel.s(10)
            y: panel.s(9)
            text: root.vistaLabel || root.message
            textFormat: Text.PlainText
            color: "#000000"
            font.family: "Segoe UI"
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: panel.s(10)
            y: panel.s(9)
            text: root.message
            textFormat: Text.PlainText
            color: "#000000"
            font.family: "Segoe UI"
            font.pixelSize: Style.font.bodySmall
          }

          // [Progress.Bar] track, 9-slice 4,4,3,3, and the chunks inside it.
          VistaArt {
            id: track
            x: osdIcon.x + osdIcon.width + panel.s(10)
            y: panel.s(28)
            width: parent.width - x - panel.s(10)
            height: panel.s(17)
            source: VistaScheme.art("progress-track")
            margins: [4, 4, 3, 3]
            readonly property int inner: width - panel.s(6)
            readonly property int pitch: panel.s(8)
            Row {
              x: panel.s(3)
              y: panel.s(3)
              spacing: panel.s(2)
              Repeater {
                model: root.hasProgress && root.maxValue > 0
                  ? Math.round(Math.min(1, root.value / root.maxValue) * Math.floor((track.inner + panel.s(2)) / track.pitch)) : 0
                Image {
                  width: panel.s(6)
                  height: track.height - panel.s(6)
                  source: VistaScheme.art("progress-chunk")
                  smooth: false
                }
              }
            }
          }
        }
      }
    }

    // Value-less messages (layout, power, media): an Vista tooltip.
    Rectangle {
      visible: !root.hasProgress && root.message !== ""
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: panel.s(8)
      anchors.bottomMargin: root.barClearance + panel.s(4)
      width: tip.implicitWidth + panel.s(10)
      height: tip.implicitHeight + panel.s(6)
      color: VistaScheme.infoWindow
      border.width: Math.max(1, panel.s(1))
      border.color: "#000000"
      Text {
        id: tip
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.maxMessageWidth)
        text: root.message
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: VistaScheme.infoText
        font.family: "Segoe UI"
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
