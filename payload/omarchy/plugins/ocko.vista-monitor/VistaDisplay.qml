import QtQuick
import qs.Commons
import "../../vista/qml"

// Vista's Display Settings (Monitor tab) over the stock monitor panel's
// model. `host` is the panel (ocko.vista-monitor Panel.qml) or, for the
// screenshot harness, a mock with the same members; nothing here runs a
// command itself.
//
// Geometry is themeui.dll's own templates (Vista SP3), converted from dialog
// units at Tahoma 8 / 96 dpi (1 DLU = 1.5 px across, 13/8 px down):
//   1008  Settings with several monitors (arrangement, Display combo,
//         Screen resolution / Color quality groups, Extend checkbox,
//         Identify / Troubleshoot / Advanced), 252 x 218
//   1007  Settings with one monitor (the monitor bitmap, 126, instead)
//   1014  the "Font size" group (237 x 30), for stock's text size
// Screen resolution's Less/More trackbar holds brightness, Color quality's
// combo holds scale; neither has an Vista control of its own.
//
// host reads:  displays, enabledDisplayCount, brightnessAvailable,
//   brightnessPercent, scaleValues, focusedMonitor, internalMonitor,
//   externalMonitor, mirrorEnabled, textSizeStops, focusSection,
//   selectedIndex, cursorActive
// host calls:  brightnessName, previewBrightness, vistaBrightnessReleased,
//   effectiveScale, activeScaleIndex, setScale, currentTextIndex,
//   adjustTextSize, toggleDisplay, close
VistaPropertySheet {
  id: sheet

  required property var host

  readonly property var displays: host.displays || []
  readonly property bool multi: displays.length > 1
  readonly property int focusedIndex: {
    for (var i = 0; i < displays.length; i++) if (displays[i] && displays[i].focused) return i
    return 0
  }
  // The display the combo, the arrangement and Extend act on: the keyboard
  // cursor's row while it is in the displays, else the last one clicked,
  // else the focused one.
  property int picked: -1
  readonly property bool monitorsCursor: host.cursorActive && host.focusSection === "monitors"
  readonly property int sel: monitorsCursor ? host.selectedIndex
                             : picked >= 0 && picked < displays.length ? picked : focusedIndex
  readonly property var selDisplay: sel >= 0 && sel < displays.length ? displays[sel] : null
  readonly property bool selCanToggle: !!selDisplay && (!selDisplay.enabled || host.enabledDisplayCount > 1)

  function du(x) { return Style.space(Math.round(x * 1.5)) }
  function dv(y) { return Style.space(Math.round(y * 13 / 8)) }

  function displayLabel(d, i) {
    if (!d) return ""
    var s = (i + 1) + ". " + d.name
    if (d.name === host.internalMonitor) s += " (built-in)"
    if (host.mirrorEnabled && d.name === host.externalMonitor) s += " (mirrored)"
    if (d.width > 0 && d.height > 0) s += " on " + d.width + " x " + d.height
    return s
  }

  function cursorTo(section, index) {
    host.cursorActive = true
    host.focusSection = section
    host.selectedIndex = index
  }

  function pick(i) {
    picked = i
    cursorTo("monitors", i)
  }

  // Esc closes an open drop list first; true when it did.
  function dismiss() {
    var combos = [displayCombo, scaleCombo, textCombo]
    for (var i = 0; i < combos.length; i++) if (combos[i].open) { combos[i].open = false; return true }
    return false
  }

  // Template y positions (DLU); the text-size group is inserted under the
  // two groups and pushes Extend and the buttons down by 33.
  readonly property int groupsY: multi ? 128 : 151
  readonly property int textY: groupsY + 46
  readonly property int extendY: textY + 33
  readonly property int buttonsY: multi ? extendY + 17 : textY + 35

  title: "Display Settings"
  titleIcon: VistaScheme.graphics + "/desk/16/100.png"
  buttons: ["close"]
  onCloseClicked: host.close()
  titles: ["Monitor"]
  tab: 0
  pageWidth: du(252)
  pageHeight: dv(buttonsY + 14 + 4)
  buttonLabels: ["<u>C</u>lose"]
  onButtonClicked: host.close()

  // One monitor in the arrangement: the desktop colour with its number,
  // Vista's selection frame round the picked one, grey when switched off.
  component MonitorBox: Rectangle {
    id: box
    required property var display
    required property int index
    readonly property bool picked: index === sheet.sel
    color: display.enabled ? "#3A6EA5" : VistaScheme.sc.face
    border.width: 1
    border.color: "#000000"
    Rectangle {
      anchors.fill: parent
      anchors.margins: -Style.space(2)
      visible: box.picked
      color: "transparent"
      border.width: Style.space(2)
      border.color: VistaScheme.sc.highlight
    }
    Text {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: Style.space(1)
      anchors.verticalCenterOffset: Style.space(1)
      text: box.index + 1
      color: "#000000"
      font.family: "Segoe UI"
      font.bold: true
      font.pixelSize: Math.min(box.height * 0.6, Style.space(28))
      visible: box.display.enabled
    }
    Text {
      anchors.centerIn: parent
      text: box.index + 1
      color: box.display.enabled ? "#FFFFFF" : VistaScheme.sc.gray
      font.family: "Segoe UI"
      font.bold: true
      font.pixelSize: Math.min(box.height * 0.6, Style.space(28))
    }
    MouseArea {
      anchors.fill: parent
      onClicked: sheet.pick(box.index)
    }
    VistaToolTip {
      visible: tipHover.hovered
      y: box.height + Style.space(2)
      text: sheet.displayLabel(box.display, box.index)
    }
    HoverHandler { id: tipHover }
  }

  Item {
    parent: sheet.page
    anchors.fill: parent

    // ---- arrangement (1008: 1819, 1801) or the monitor bitmap (1007: 1812)
    VistaLabel {
      visible: sheet.multi
      x: sheet.du(7)
      y: sheet.dv(7)
      width: sheet.du(238)
      wrapMode: Text.WordWrap
      text: "Click a monitor icon to pick the display to change."
    }

    Rectangle {
      id: arrangement
      visible: sheet.multi
      x: sheet.du(7)
      y: sheet.dv(18)
      width: sheet.du(238)
      height: sheet.dv(82)
      color: VistaScheme.sc.face
      border.width: 1
      border.color: "#000000"

      // Side by side in output order, scaled so the row fits, bottoms
      // aligned (Hyprland's own layout positions aren't in stock's model).
      readonly property real gap: Style.space(6)
      readonly property real totalW: {
        var t = 0
        for (var i = 0; i < sheet.displays.length; i++) t += Math.max(1, sheet.displays[i].width || 1920)
        return t
      }
      readonly property real maxH: {
        var m = 1
        for (var i = 0; i < sheet.displays.length; i++) m = Math.max(m, sheet.displays[i].height || 1080)
        return m
      }
      readonly property real k: Math.min((width - Style.space(24) - gap * Math.max(0, sheet.displays.length - 1)) / totalW,
                                         (height - Style.space(20)) / maxH)

      Row {
        anchors.centerIn: parent
        spacing: arrangement.gap
        Repeater {
          model: sheet.displays.length
          Item {
            required property int index
            readonly property var d: sheet.displays[index]
            width: Math.round((d.width || 1920) * arrangement.k)
            height: Math.round(arrangement.maxH * arrangement.k)
            MonitorBox {
              display: parent.d
              index: parent.index
              anchors.bottom: parent.bottom
              width: parent.width
              height: Math.round((parent.d.height || 1080) * arrangement.k)
            }
          }
        }
      }
    }

    // Vista's Display Settings drew each monitor as a blue rounded panel
    // with its number, in the screen's proportions.
    Rectangle {
      visible: !sheet.multi
      readonly property var d: sheet.displays[0] || ({})
      readonly property real aspect: (d.width || 16) / Math.max(1, d.height || 9)
      height: sheet.dv(80)
      width: Math.min(sheet.du(150), height * aspect)
      x: (parent.width - width) / 2
      y: sheet.dv(7) + (sheet.dv(107) - height) / 2
      radius: Style.space(3)
      border.width: 2
      border.color: "#3A6EA5"
      gradient: Gradient {
        GradientStop { position: 0; color: "#8DB8E8" }
        GradientStop { position: 1; color: "#3D7BC4" }
      }
      Text {
        anchors.centerIn: parent
        text: "1"
        color: "#FFFFFF"
        font.family: "Segoe UI"
        font.pixelSize: Style.space(44)
        style: Text.Raised; styleColor: "#40000000"
      }
    }

    // ---- Display: (1820) and its combo (1800) / static (1811) ----------
    VistaLabel {
      x: sheet.du(7)
      y: sheet.dv(sheet.multi ? 102 : 124)
      text: "<u>D</u>isplay:"
    }
    VistaLabel {
      visible: !sheet.multi
      x: sheet.du(7)
      y: sheet.dv(134)
      width: sheet.du(238)
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: sheet.displays.length ? sheet.displayLabel(sheet.displays[0], 0) : "(no display)"
    }

    // ---- Screen resolution (1818) holds brightness ---------------------
    VistaGroupBox {
      x: sheet.du(7)
      y: sheet.dv(sheet.groupsY)
      width: sheet.du(115)
      height: sheet.dv(43)
      caption: "Brightness"
      enabled: sheet.host.brightnessAvailable
    }
    VistaLabel {
      x: sheet.du(13)
      y: sheet.dv(sheet.groupsY + 10) + (sheet.dv(17) - height) / 2
      text: "Less"
      enabled: sheet.host.brightnessAvailable
    }
    VistaTrackbar {
      id: brightTrack
      x: sheet.du(32)
      y: sheet.dv(sheet.groupsY + 10)
      width: sheet.du(62)
      height: sheet.dv(17)
      from: 1
      to: 100
      stepSize: 1
      pageSize: 10
      tickCount: 11
      enabled: sheet.host.brightnessAvailable
      focused: sheet.host.cursorActive && sheet.host.focusSection === "brightness"
      value: sheet.host.brightnessPercent
      onMoved: function(v) {
        sheet.cursorTo("brightness", -1)
        sheet.host.previewBrightness(v)
      }
      onPressedChanged: if (!pressed) sheet.host.vistaBrightnessReleased(dragValue)
    }
    VistaLabel {
      x: sheet.du(97)
      y: sheet.dv(sheet.groupsY + 10) + (sheet.dv(17) - height) / 2
      text: "More"
      enabled: sheet.host.brightnessAvailable
    }
    VistaLabel {
      x: sheet.du(14)
      y: sheet.dv(sheet.groupsY + 30)
      width: sheet.du(100)
      horizontalAlignment: Text.AlignHCenter
      enabled: sheet.host.brightnessAvailable
      text: {
        if (!sheet.host.brightnessAvailable) return "Fixed brightness"
        var p = Math.round(brightTrack.shown)
        return p + "% (" + sheet.host.brightnessName(p) + ")"
      }
    }

    // ---- Color quality (1817) holds scale -------------------------------
    VistaGroupBox {
      x: sheet.du(129)
      y: sheet.dv(sheet.groupsY)
      width: sheet.du(116)
      height: sheet.dv(43)
      caption: "Scale"
    }
    VistaLabel {
      // stock names the monitor only when more than one is in play
      visible: sheet.host.focusedMonitor !== "" && sheet.host.enabledDisplayCount > 1
      x: sheet.du(135)
      y: sheet.dv(sheet.groupsY + 28)
      width: sheet.du(103)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "Applies to " + sheet.host.focusedMonitor
    }

    // ---- Font size (1014: 1216) holds text size -------------------------
    VistaGroupBox {
      x: sheet.du(7)
      y: sheet.dv(sheet.textY)
      width: sheet.du(238)
      height: sheet.dv(30)
      caption: "Text size"
    }
    VistaLabel {
      x: sheet.du(177)
      y: sheet.dv(sheet.textY + 12) + (sheet.dv(12) - height) / 2
      width: sheet.du(62)
      textFormat: Text.PlainText
      text: "Shell and GTK"
    }

    // ---- Extend (1008: 1805) toggles the picked display -----------------
    VistaCheckBox {
      visible: sheet.multi
      x: sheet.du(7)
      y: sheet.dv(sheet.extendY)
      text: "<u>E</u>xtend my desktop onto this monitor."
      enabled: sheet.selCanToggle
      checked: !!sheet.selDisplay && sheet.selDisplay.enabled
      focused: sheet.monitorsCursor
      onToggled: if (sheet.selDisplay) sheet.host.toggleDisplay(sheet.selDisplay.name, sheet.selDisplay.enabled)
    }

    // ---- Identify / Troubleshoot / Advanced: nothing behind them here ---
    Row {
      x: sheet.du(sheet.multi ? 68 : 126)
      y: sheet.dv(sheet.buttonsY)
      spacing: sheet.du(4) - Style.space(3)
      VistaButton { visible: sheet.multi; text: "<u>I</u>dentify"; enabled: false; width: sheet.du(56) }
      VistaButton { text: "<u>T</u>roubleshoot..."; enabled: false; width: sheet.du(59) }
      VistaButton { text: "Ad<u>v</u>anced"; enabled: false; width: sheet.du(56) }
    }

    // The drop-down combos last, so an open list sits over everything.
    VistaComboBox {
      id: textCombo
      z: 3
      x: sheet.du(13)
      y: sheet.dv(sheet.textY + 12)
      width: sheet.du(160)
      model: (sheet.host.textSizeStops || []).map(function(px) { return px + " px" })
      currentIndex: sheet.host.currentTextIndex()
      focused: sheet.host.cursorActive && sheet.host.focusSection === "textsize"
      visibleRows: model.length
      onActivated: function(i) {
        sheet.cursorTo("textsize", -1)
        var d = i - sheet.host.currentTextIndex()
        if (d !== 0) sheet.host.adjustTextSize(d)
      }
    }
    VistaComboBox {
      id: scaleCombo
      z: 4
      x: sheet.du(135)
      y: sheet.dv(sheet.groupsY + 11)
      width: sheet.du(103)
      readonly property bool cursorHere: sheet.host.cursorActive && sheet.host.focusSection === "scale"
      model: (sheet.host.scaleValues || []).map(function(v) { return sheet.host.effectiveScale(v) + "x" })
      // Vista moves a closed list's selection with the arrows; stock applies
      // the cursor's preset on Enter, so the combo shows the cursor's.
      currentIndex: cursorHere ? sheet.host.selectedIndex : sheet.host.activeScaleIndex()
      focused: cursorHere
      visibleRows: model.length
      onActivated: function(i) {
        sheet.cursorTo("scale", i)
        sheet.host.setScale(sheet.host.scaleValues[i])
      }
    }
    VistaComboBox {
      id: displayCombo
      visible: sheet.multi
      z: 5
      x: sheet.du(7)
      y: sheet.dv(111)
      width: sheet.du(238)
      model: sheet.displays.map(function(d, i) { return sheet.displayLabel(d, i) })
      currentIndex: sheet.sel
      visibleRows: model.length
      onActivated: function(i) { sheet.pick(i) }
    }
  }
}
