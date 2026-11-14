import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "../../vista/qml"

// The Windows Vista Sidebar: a 150 px strip on the right edge of the desktop
// (sidebar.exe RCDATA 20001, the right-docked shade) with the "+ < >" control
// at the top and four gadgets, each from its own gadget folder's art
// (assets/gadgets/<Name>.Gadget/images; positions measured on that art):
//   Clock      trad face, hands and highlights, ticking by the second
//   CPU Meter  CPU (large dial) and memory (small dial) from /proc, every 2 s
//   Slide Show the Vista wallpapers, 30 s each
//   Weather    the stock weather source (wttr.in, the location Omarchy's
//              weather setting holds), every 30 min
// Off by default; the state is ~/.local/state/omarchy/vista/sidebar ("on").
// Nothing runs while it is hidden or a non-Vista theme is active: every timer
// and SystemClock is bound to `live`.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string gadgets: "file://" + home + "/.config/omarchy/vista/assets/gadgets/"
  readonly property string sbArt: "file://" + home + "/.config/omarchy/vista/assets/graphics/sidebar/RCDATA/"
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/vista/sidebar"

  property bool shown: false
  readonly property bool live: shown && VistaScheme.vistaActive

  function s(n) { return Style.space(n) }
  function setShown(on) {
    shown = on
    stateFile.setText(on ? "on\n" : "off\n")
  }

  FileView {
    id: stateFile
    path: root.statePath
    blockLoading: true
    printErrors: false
    onLoaded: root.shown = String(text()).trim() === "on"
  }

  // Vista: ShellIpc (4.5 qs.Commons) so omarchy-shell answers over its socket.
  ShellIpc {
    target: "vistasidebar"
    function toggle(): string { root.setShown(!root.shown); return root.shown ? "on" : "off" }
    function show(): string { root.setShown(true); return "on" }
    function hide(): string { root.setShown(false); return "off" }
    function state(): string { return root.shown ? "on" : "off" }
  }

  // ---- CPU and memory (/proc), only while live
  property var lastCpu: null
  property real cpu: 0
  property real mem: 0
  FileView { id: procStat; path: "/proc/stat"; blockLoading: true; printErrors: false }
  FileView { id: procMem; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
  function sampleCpu() {
    procStat.reload()
    var f = String(procStat.text()).split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
    var idle = f[3] + (f[4] || 0), total = 0
    for (var i = 0; i < f.length; i++) total += f[i]
    if (lastCpu && total > lastCpu.total) cpu = 1 - (idle - lastCpu.idle) / (total - lastCpu.total)
    lastCpu = { idle: idle, total: total }
    procMem.reload()
    var m = {}, lines = String(procMem.text()).split("\n")
    for (var j = 0; j < lines.length; j++) {
      var kv = lines[j].split(":")
      if (kv.length === 2) m[kv[0]] = parseInt(kv[1])
    }
    if (m.MemTotal > 0) mem = 1 - (m.MemAvailable || 0) / m.MemTotal
  }
  Timer {
    interval: 2000
    running: root.live
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleCpu()
  }

  // ---- Weather: the stock source and location setting
  property string weatherIcon: "loading"
  property string weatherTemp: ""
  property string weatherPlace: ""
  readonly property bool fahrenheit: Qt.locale().measurementSystem === Locale.ImperialUSSystem
  FileView {
    id: weatherSetting
    path: root.home + "/.local/state/omarchy/settings/weather.json"
    blockLoading: true
    printErrors: false
  }
  function weatherQuery() {
    try {
      var w = JSON.parse(weatherSetting.text())
      if (w.latitude !== undefined && w.longitude !== undefined) return w.latitude + "," + w.longitude
      if (w.name) return encodeURIComponent(w.name)
    } catch (e) {}
    return ""
  }
  // wttr.in weather codes -> the gadget's docked_<condition>.png
  function weatherKind(code) {
    var c = Number(code)
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
  Process {
    id: weatherProc
    command: ["curl", "-fsS", "--max-time", "15", "https://wttr.in/" + root.weatherQuery() + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var j = JSON.parse(text)
          var now = j.current_condition[0]
          root.weatherIcon = root.weatherKind(now.weatherCode)
          root.weatherTemp = (root.fahrenheit ? now.temp_F : now.temp_C) + "°"
          var a = j.nearest_area && j.nearest_area[0]
          root.weatherPlace = a ? a.areaName[0].value + ", " + (a.region[0].value || a.country[0].value) : ""
        } catch (e) {}
      }
    }
  }
  Timer {
    interval: 30 * 60 * 1000
    running: root.live
    repeat: true
    triggeredOnStart: true
    onTriggered: { weatherSetting.reload(); if (!weatherProc.running) weatherProc.running = true }
  }

  // ---- Slide Show: the Vista wallpapers, 30 s each
  FolderListModel {
    id: slides
    folder: "file://" + root.home + "/.config/omarchy/vista/assets/wallpapers"
    nameFilters: ["*.jpg", "*.png"]
    showDirs: false
  }
  property int slide: 0
  Timer {
    interval: 30000
    running: root.live && slides.count > 1
    repeat: true
    onTriggered: root.slide = (root.slide + 1) % slides.count
  }

  SystemClock {
    id: tick
    precision: SystemClock.Seconds
    enabled: root.live
  }

  // ---- the strip
  PanelWindow {
    id: strip
    visible: root.live
    anchors { top: true; bottom: true; right: true }
    implicitWidth: root.s(150)
    color: "transparent"
    WlrLayershell.namespace: "vista-sidebar"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    Image {
      anchors.fill: parent
      source: root.sbArt + "20001.png"
      fillMode: Image.Stretch
    }

    // "+ < >": gadget gallery and page buttons (drawn; the four gadgets are
    // fixed here). 20x20 frames: normal, hot, pressed, disabled.
    Rectangle {
      id: pill
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.s(8)
      width: root.s(74); height: root.s(20)
      radius: height / 2
      color: "#40000000"
      border.color: "#50FFFFFF"
      Row {
        anchors.centerIn: parent
        spacing: root.s(4)
        Repeater {
          model: ["20006", "20004", "20005"]
          Image {
            required property var modelData
            width: root.s(20); height: root.s(20)
            source: root.sbArt + modelData + ".png"
            sourceClipRect: Qt.rect(0, (pm.pressed ? 2 : pm.containsMouse ? 1 : (modelData === "20006" ? 0 : 3)) * 20, 20, 20)
            MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true }
          }
        }
      }
    }

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      y: pill.y + pill.height + root.s(10)
      spacing: root.s(12)

      // Clock (trad): hands 13x129 turn about the face centre.
      Item {
        width: root.s(130); height: root.s(130)
        readonly property var t: tick.date
        readonly property string g: root.gadgets + "Clock.Gadget/images/trad"
        Image { anchors.fill: parent; source: parent.g + ".png"; smooth: true }
        Repeater {
          model: [["_h", (parent.t.getHours() % 12) * 30 + parent.t.getMinutes() / 2],
                  ["_m", parent.t.getMinutes() * 6], ["_s", parent.t.getSeconds() * 6]]
          Image {
            required property var modelData
            anchors.centerIn: parent
            width: root.s(13); height: root.s(129)
            source: parent.g + modelData[0] + ".png"
            rotation: modelData[1]
            smooth: true; antialiasing: true
          }
        }
        Image { anchors.centerIn: parent; width: root.s(13); height: root.s(129); source: parent.g + "_dot.png"; smooth: true }
        Image { anchors.fill: parent; source: parent.g + "_highlights.png"; smooth: true }
      }

      // CPU Meter: dials at (43,57) and (94,34) on the 130x103 back; the
      // needles sweep -120..120 degrees.
      Item {
        width: root.s(130); height: root.s(103)
        readonly property string g: root.gadgets + "CPU.Gadget/images/"
        Image { anchors.fill: parent; source: parent.g + "back.png"; smooth: true }
        Image {
          x: root.s(43) - width / 2; y: root.s(57) - height / 2
          width: root.s(8); height: root.s(72)
          source: parent.g + "dial.png"
          rotation: -120 + 240 * root.cpu
          smooth: true; antialiasing: true
          Behavior on rotation { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        }
        Image {
          x: root.s(94) - width / 2; y: root.s(34) - height / 2
          width: root.s(8); height: root.s(50)
          source: parent.g + "dial_sml.png"
          rotation: -120 + 240 * root.mem
          smooth: true; antialiasing: true
          Behavior on rotation { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        }
        Image { width: root.s(130); height: root.s(101); source: parent.g + "dialdot.png"; smooth: true }
        Image { anchors.fill: parent; source: parent.g + "glass.png"; smooth: true }
        Text {
          x: root.s(43) - width / 2; y: root.s(78)
          text: Math.round(root.cpu * 100) + "%"
          color: "white"; font.family: "Segoe UI"; font.pixelSize: root.s(11)
        }
        Text {
          x: root.s(94) - width / 2; y: root.s(46)
          text: Math.round(root.mem * 100) + "%"
          color: "white"; font.family: "Segoe UI"; font.pixelSize: root.s(9)
        }
      }

      // Slide Show: the 130x100 frame (its black well starts at 4,5), then
      // the picture in the well.
      Item {
        width: root.s(130); height: root.s(100)
        Image { anchors.fill: parent; source: root.gadgets + "SlideShow.Gadget/images/in_sidebar/slideshow_glass_frame.png"; smooth: true }
        Image {
          anchors.fill: parent
          anchors.leftMargin: root.s(4); anchors.rightMargin: root.s(4)
          anchors.topMargin: root.s(5); anchors.bottomMargin: root.s(5)
          source: slides.count > 0 ? slides.get(root.slide % slides.count, "fileUrl") : ""
          fillMode: Image.PreserveAspectCrop
          sourceSize.width: root.s(240)
          asynchronous: true
          smooth: true
        }
      }

      // Weather (docked): base, condition art, temperature and place.
      Item {
        width: root.s(130); height: root.s(67)
        readonly property string g: root.gadgets + "Weather.Gadget/images/"
        Image { anchors.fill: parent; source: parent.g + "BLUEDOCKED-base.png"; smooth: true }
        Image {
          anchors.fill: parent
          source: parent.g + (root.weatherIcon === "loading" ? "docked-loading.png" : "docked_" + root.weatherIcon + ".png")
          smooth: true
        }
        Text {
          anchors.right: parent.right; anchors.rightMargin: root.s(8)
          y: root.s(8)
          text: root.weatherTemp
          color: "white"; font.family: "Segoe UI"; font.pixelSize: root.s(22)
          style: Text.Raised; styleColor: "#40000000"
        }
        Text {
          anchors.right: parent.right; anchors.rightMargin: root.s(8)
          y: root.s(42)
          width: root.s(80)
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
          text: root.weatherPlace
          color: "white"; font.family: "Segoe UI"; font.pixelSize: root.s(10)
        }
      }
    }
  }
}
