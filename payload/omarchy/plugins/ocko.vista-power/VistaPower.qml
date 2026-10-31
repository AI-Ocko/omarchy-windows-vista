import QtQuick
import qs.Commons
import "../../vista/qml"

// VistaPower: Vista's Power Options Properties for ocko.vista-power. Geometry is the
// pinned binaries' own templates, converted from dialog units at Tahoma 8 /
// 96 dpi (1 DLU = 1.5 px across, 13/8 px down):
//   powercfg.cpl 100  Power Schemes, 252 x 218
//   stobject.dll 100  Power Meter (the tray's page), 252 x 218
// Power Meter's "Power status" box is filled at runtime by batmeter.dll in Vista
// (no template); its rows here hold stock's battery readout.
// `host` is duck-typed (Panel.qml, or the harness's mock): batteryInfo,
// discharging, charging, chargeThresholdActive, batteryFull, batteryFlowIdle,
// batteryFraction, heroStatusText, rotatingPhrases, profiles, activeProfile,
// profileIndex, cursorActive, showPercentage, vistaTab, setProfile(),
// togglePercentage(), close().
VistaPropertySheet {
  id: sheet

  property var host
  property real statusOpacity: 1
  readonly property bool comboOpen: schemeCombo.open
  function closeCombo() { schemeCombo.open = false }

  function s(n) { return Style.space(n) }
  function du(x) { return Style.space(Math.round(x * 1.5)) }
  function dv(y) { return Style.space(Math.round(y * 13 / 8)) }
  // Stock's button label: first letter capitalised.
  function profileLabel(p) {
    var t = String(p || "")
    return t.charAt(0).toUpperCase() + t.slice(1)
  }
  function icon(id) { return VistaScheme.graphics + "/powercfg/32/" + id + ".png" }

  readonly property int activeIndex: host.profiles.indexOf(host.activeProfile)
  readonly property string sourceLabel: host.discharging ? "Running on batteries" : "Plugged in"

  title: "Power Options Properties"
  titleIcon: VistaScheme.graphics + "/powercfg/16/202.png"
  buttons: ["help", "close"]
  disabledButtons: ["help"]
  onCloseClicked: host.close()
  titles: ["Power Schemes", "Power Meter"]
  tab: host.vistaTab
  onTabClicked: function(i) { schemeCombo.open = false; host.vistaTab = i }
  pageWidth: du(252)
  pageHeight: dv(218)
  // Stock applies a profile the moment it is picked, so there is nothing
  // for Apply to do; OK and Cancel both close.
  buttonLabels: ["OK", "Cancel", "<u>A</u>pply"]
  disabledButtonIndices: [2]
  onButtonClicked: host.close()

  // -- Power Schemes (powercfg.cpl 100) --
  Item {
    parent: sheet.page
    anchors.fill: parent
    visible: sheet.tab === 0

    Image {
      x: sheet.du(7); y: sheet.dv(7)
      width: sheet.s(32); height: sheet.s(32)
      source: sheet.icon(202)
    }
    VistaLabel {
      x: sheet.du(39); y: sheet.dv(7); width: sheet.du(206)
      wrapMode: Text.WordWrap
      text: "Select the power scheme with the most appropriate settings for this computer. The scheme you select takes effect at once."
    }

    VistaGroupBox { x: sheet.du(7); y: sheet.dv(38); width: sheet.du(238); height: sheet.dv(52); caption: "Power schemes" }
    VistaButton {
      x: sheet.du(134); y: sheet.dv(69); width: sheet.du(50); height: sheet.dv(14)
      text: "<u>S</u>ave As..."
      enabled: false
    }
    VistaButton {
      x: sheet.du(188); y: sheet.dv(69); width: sheet.du(50); height: sheet.dv(14)
      text: "<u>D</u>elete"
      enabled: false
    }

    VistaGroupBox {
      x: sheet.du(7); y: sheet.dv(97); width: sheet.du(238); height: sheet.dv(113)
      caption: sheet.activeIndex >= 0 ? "Settings for " + sheet.profileLabel(host.activeProfile) + " power scheme" : "Settings"
    }
    VistaLabel { x: sheet.du(14); y: sheet.dv(111); text: "When computer is:" }
    Image {
      x: sheet.du(87); y: sheet.dv(106)
      width: sheet.s(32); height: sheet.s(32)
      source: sheet.icon(200)
    }
    VistaLabel { x: sheet.du(113); y: sheet.dv(111); text: "Plugged in" }
    Image {
      x: sheet.du(161); y: sheet.dv(106)
      width: sheet.s(32); height: sheet.s(32)
      source: sheet.icon(201)
    }
    VistaLabel {
      x: sheet.du(184); y: sheet.dv(108); width: sheet.du(40)
      wrapMode: Text.WordWrap
      text: "Running on batteries"
    }
    VistaLabel { x: sheet.du(14); y: sheet.dv(131); text: "Power scheme:" }
    // Omarchy keeps a profile per power source and reports only the
    // current one, so only the current source's column has a value.
    VistaLabel {
      x: sheet.du(host.discharging ? 166 : 87); y: sheet.dv(131)
      text: sheet.activeIndex >= 0 ? sheet.profileLabel(host.activeProfile) : "(none)"
    }
    VistaEtched { x: sheet.du(14); y: sheet.dv(166); width: sheet.du(224) }
    VistaLabel {
      x: sheet.du(14); y: sheet.dv(175); width: sheet.du(224)
      wrapMode: Text.WordWrap
      text: host.profiles.length > 0
        ? "Choosing a scheme above sets it for the current power source (" + sheet.sourceLabel.toLowerCase() + ")."
        : "No power profiles are available. power-profiles-daemon is not running."
    }

    // Declared last so its list opens over the groups below it.
    VistaComboBox {
      id: schemeCombo
      x: sheet.du(14); y: sheet.dv(49); width: sheet.du(224)
      z: 10
      enabled: host.profiles.length > 0
      model: host.profiles.map(function(p) { return sheet.profileLabel(p) })
      currentIndex: host.cursorActive ? host.profileIndex : sheet.activeIndex
      focused: host.cursorActive
      onActivated: function(i) { host.setProfile(host.profiles[i]) }
    }
  }

  // -- Power Meter (stobject.dll 100) --
  Item {
    parent: sheet.page
    anchors.fill: parent
    visible: sheet.tab === 1

    // Vista's "Always show icon on the taskbar." holds stock's right-click
    // toggle: the percentage beside the tray icon.
    VistaCheckBox {
      x: sheet.du(6); y: sheet.dv(6)
      text: "Show <u>p</u>ercentage on the taskbar."
      checked: host.showPercentage
      onToggled: host.togglePercentage()
    }
    // One display device: nothing to break down per battery.
    VistaCheckBox {
      x: sheet.du(135); y: sheet.dv(6)
      text: "Show details for each <u>b</u>attery."
      enabled: false
    }

    VistaGroupBox { x: sheet.du(9); y: sheet.dv(20); width: sheet.du(234); height: sheet.dv(189); caption: "Power status" }

    VistaLabel { x: sheet.du(17); y: sheet.dv(33); text: "Current power source:" }
    VistaLabel { x: sheet.du(130); y: sheet.dv(33); text: host.discharging ? "Batteries" : "AC power" }
    VistaLabel { x: sheet.du(17); y: sheet.dv(45); text: "Total battery power remaining:" }
    VistaLabel { x: sheet.du(130); y: sheet.dv(45); text: host.batteryInfo.percentage || "—" }

    Image {
      x: sheet.du(17); y: sheet.dv(62)
      width: sheet.s(32); height: sheet.s(32)
      source: sheet.icon(host.charging ? 202 : 201)
    }
    VistaProgress {
      x: sheet.du(45); y: sheet.dv(63); width: sheet.du(188); height: sheet.s(18)
      value: host.batteryFraction
    }
    // Stock's status line: "Fully charged", the rotating phrase while
    // current flows, or the mode label.
    VistaLabel {
      x: sheet.du(45); y: sheet.dv(78); width: sheet.du(188)
      textFormat: Text.PlainText
      elide: Text.ElideRight
      opacity: sheet.statusOpacity
      text: host.heroStatusText + (host.rotatingPhrases ? "..." : "")
    }

    VistaEtched { x: sheet.du(17); y: sheet.dv(94); width: sheet.du(218) }

    // Stock's stats, shown once data has ever loaded (stock's own guard).
    Item {
      anchors.fill: parent
      visible: host.batteryInfo.percentage !== undefined

      VistaLabel { x: sheet.du(17); y: sheet.dv(103); text: "Battery size:" }
      VistaLabel { x: sheet.du(130); y: sheet.dv(103); text: host.batteryInfo.size || "" }
      VistaLabel { x: sheet.du(17); y: sheet.dv(115); text: "Charge cycles:" }
      VistaLabel { x: sheet.du(130); y: sheet.dv(115); text: host.batteryInfo.cycles || "—" }
      VistaLabel {
        x: sheet.du(17); y: sheet.dv(127)
        text: (host.chargeThresholdActive ? "Charge limit" : (host.discharging ? "Time left" : "Time to full")) + ":"
      }
      VistaLabel {
        x: sheet.du(130); y: sheet.dv(127)
        text: host.chargeThresholdActive ? (host.batteryInfo.threshold || "-") : (host.batteryFlowIdle ? "-" : (host.batteryInfo.time || "—"))
      }
      VistaLabel {
        x: sheet.du(17); y: sheet.dv(139)
        text: (host.chargeThresholdActive ? "Battery state" : (host.discharging ? "Discharging" : "Charging")) + ":"
      }
      VistaLabel {
        x: sheet.du(130); y: sheet.dv(139)
        text: host.chargeThresholdActive ? "Holding" : (host.batteryFull ? "-" : (host.batteryInfo.rate || ""))
      }
    }
  }
}
