// ocko.vista-clock: omarchy.clock's calendar for the Vista notification area (Windows
// Vista theme only; see omarchy/vista/bin/vista-mode). Lines 9-250 are the logic of
// /usr/share/omarchy/shell/plugins/panels/clock/Panel.qml (Omarchy 4.0.6,
// sha256 ff6062b3a5714a727c345d239449d460c95e6087c99f4cda786942c33cdaa612,
// lines 1-240), with each change marked "Vista:". The card below that is rebuilt
// as timedate.cpl's Date and Time Properties.
// Re-diff the logic against a newer Omarchy: diff <(sed -n 9,250p Panel.qml) <(sed -n 1,240p <stock>)

import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import Quickshell.Io  // Vista: timedatectl
import "../../vista/qml"  // Vista

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  // Local noon, so a first of the month with no midnight (Havana, April 2012)
  // still names its own month; UTC would name the previous one west of Greenwich.
  readonly property date viewDate: new Date(viewYear, viewMonth, 1, 12)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }


  // =========================================================================
  // Vista UI (ocko.vista-clock). Everything above is stock (see the header) apart
  // from the lines marked "Vista:". Everything below replaces stock's card.
  //
  // Geometry is timedate.cpl's own dialog templates (Vista SP2), converted from
  // dialog units at Tahoma 8 / 96 dpi (1 DLU = 1.5 px across, 13/8 px down):
  //   1  Date & Time, 252 x 146
  //   2  Time Zone, 252 x 152 (the world map is the cpl's BITMAP 50)
  //   3  Internet Time, 252 x 152
  // The Calendar tab has no Vista original: it holds stock's year progress and
  // Memento Mori. Setting the clock needs root, so those controls show
  // disabled; the month and year controls only browse, as stock's do.
  // =========================================================================

  property int sheetTab: 0
  // One `timedatectl show` (plus show-timesync, for the server) per open.
  property var tdInfo: ({})

  // Stock's commitLife/startEditingLife read these by name.
  readonly property var bornField: bornBox.input
  readonly property var expectancyField: lifeBox.input

  function s(n) { return Style.space(n) }
  function du(x) { return Style.space(Math.round(x * 1.5)) }
  function dv(y) { return Style.space(Math.round(y * 13 / 8)) }

  function vistaBareCard(item) {
    var card = item && item.parent ? item.parent.parent : null
    if (card && "radius" in card) {
      card.color = "transparent"
      card.radius = 0
    }
  }

  // "(GMT+01:00) Europe/Berlin": Vista's offset prefix, then the zone.
  readonly property string tzLabel: {
    var off = -today.getTimezoneOffset()
    var sign = off < 0 ? "-" : "+"
    off = Math.abs(off)
    function two(n) { return n < 10 ? "0" + n : String(n) }
    return "(GMT" + sign + two(Math.floor(off / 60)) + ":" + two(off % 60) + ") " + (tdInfo.Timezone || "Local time")
  }

  Connections {
    target: root
    function onOpenedChanged() { if (root.opened && !tdProc.running) tdProc.running = true }
  }

  Process {
    id: tdProc
    command: ["bash", "-c", "timedatectl show; timedatectl show-timesync"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = {}
        var lines = String(text).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var eq = lines[i].indexOf("=")
          if (eq > 0) out[lines[i].slice(0, eq)] = lines[i].slice(eq + 1)
        }
        root.tdInfo = out
      }
    }
    stderr: SplitParser { onRead: function(line) { if (line) console.warn("ocko.vista-clock: timedatectl: " + line) } }
  }

  // The analog clock ticks by the second, and only while the sheet is open.
  SystemClock {
    id: vistaTick
    precision: SystemClock.Seconds
    enabled: root.opened
  }

  // ---- inline components (declared before use) ----------------------------

  // [Spin.Up] over [Spin.Down], each 4 frames (normal, hot, pressed,
  // disabled) with its glyph.
  component VistaSpin: Column {
    id: spin
    signal stepped(int delta)
    Repeater {
      model: ["up", "down"]
      Item {
        id: half
        required property var modelData
        width: spin.width
        height: spin.height / 2
        readonly property int frame: !spin.enabled ? 3 : hm.pressed ? 2 : hm.containsMouse ? 1 : 0
        VistaArt {
          anchors.fill: parent
          source: VistaScheme.art("spin-" + half.modelData + "-" + half.frame)
          margins: [4, 4, 4, 4]
        }
        Image {
          anchors.centerIn: parent
          width: root.s(7)
          height: root.s(6)
          source: VistaScheme.art("spin-" + half.modelData + "g-" + half.frame)
        }
        MouseArea {
          id: hm
          anchors.fill: parent
          hoverEnabled: true
          enabled: spin.enabled
          onClicked: spin.stepped(half.modelData === "up" ? 1 : -1)
        }
      }
    }
  }

  // A clock hand: a bar from the centre of its parent, rotated about its base.
  component Hand: Rectangle {
    property real angle: 0
    property real length: 0
    x: parent.width / 2 - width / 2
    y: parent.height / 2 - length
    height: length
    antialiasing: true
    transformOrigin: Item.Bottom
    rotation: angle
  }

  // ---- the panel ------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    padding: 0
    borderSpec: Border.none()
    contentWidth: sheet.width
    contentHeight: sheet.height

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      Component.onCompleted: root.vistaBareCard(keyCatcher)
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      VistaPropertySheet {
        id: sheet
        title: "Date and Time Properties"
        buttons: ["help", "close"]
        disabledButtons: ["help"]
        onCloseClicked: root.close()
        titles: ["Date & Time", "Time Zone", "Internet Time", "Calendar"]
        tab: root.sheetTab
        onTabClicked: function(i) { root.sheetTab = i }
        pageWidth: root.du(252)
        pageHeight: root.dv(152)
        buttonLabels: ["OK", "Cancel", "<u>A</u>pply"]
        disabledButtonIndices: [2]
        onButtonClicked: root.close()

        // -- Date & Time (template 1) --
        Item {
          parent: sheet.page
          anchors.fill: parent
          visible: root.sheetTab === 0

          VistaGroupBox { x: root.du(4); y: root.dv(2); width: root.du(122); height: root.dv(125); caption: "Date" }
          VistaComboBox {
            x: root.du(11); y: root.dv(17); width: root.du(50)
            z: 5
            model: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(function(m) { return root.labelLocale.monthName(m, Locale.LongFormat) })
            currentIndex: root.viewMonth
            visibleRows: 12
            onActivated: function(i) { root.viewMonth = i; open = false }
          }
          VistaTextField {
            x: root.du(68); y: root.dv(17); width: root.du(42); height: root.dv(13)
            readOnly: true
            text: String(root.viewYear)
          }
          VistaSpin {
            x: root.du(110); y: root.dv(17); width: root.du(8); height: root.dv(13)
            onStepped: function(d) { root.moveYear(d) }
          }

          // The calendar (CalWndMain), with the ISO week column of answer 10
          // on its left; "Wk" is stock's week-start toggle.
          Rectangle {
            id: cal
            x: root.du(11); y: root.dv(37); width: root.du(108); height: root.dv(80)
            color: "#FFFFFF"
            border.width: 1
            border.color: VistaScheme.sc.edit
            readonly property real colW: (width - 2) / 8
            readonly property real rowH: (height - 3) / 7

            WheelHandler {
              onWheel: function(e) { root.moveMonth(e.angleDelta.y > 0 ? -1 : 1) }
            }

            Row {
              x: 1; y: 1
              Item {
                width: cal.colW; height: cal.rowH
                VistaLabel {
                  anchors.centerIn: parent
                  text: "Wk"
                  color: VistaScheme.sc.gray
                  font.underline: wkMouse.containsMouse
                }
                MouseArea { id: wkMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleWeekStart() }
                VistaToolTip {
                  visible: wkMouse.containsMouse
                  y: parent.height + root.s(4)
                  z: 20
                  text: "Start weeks on " + root.nextWeekStartLabel
                }
              }
            }
            // Day initials, each placed by column: inside the Row above they
            // were laid out from the wrong origin (seen live, off the window).
            Repeater {
              model: root.weekdays
              VistaLabel {
                required property int index
                required property var modelData
                x: 1 + (index + 1) * cal.colW
                y: 1
                width: cal.colW; height: cal.rowH
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: String(root.labelLocale.dayName(modelData, Locale.ShortFormat)).charAt(0)
              }
            }
            Rectangle { x: 1; y: 1 + cal.rowH; width: cal.width - 2; height: 1; color: "#ACA899" }

            Column {
              x: 1; y: 2 + cal.rowH
              Repeater {
                model: root.weeks
                Row {
                  required property var modelData
                  VistaLabel {
                    width: cal.colW; height: cal.rowH
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: VistaScheme.sc.gray
                    text: modelData.week
                  }
                  Repeater {
                    model: modelData.days
                    Item {
                      required property var modelData
                      width: cal.colW; height: cal.rowH
                      Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: modelData.today && modelData.inMonth
                        color: VistaScheme.sc.highlight
                      }
                      VistaLabel {
                        anchors.centerIn: parent
                        visible: modelData.inMonth
                        text: modelData.day
                        color: modelData.today ? VistaScheme.sc.highlightText : "#000000"
                      }
                    }
                  }
                }
              }
            }
          }

          VistaGroupBox { x: root.du(132); y: root.dv(2); width: root.du(113); height: root.dv(125); caption: "Time" }
          // ClockWndMain: hour marks as raised squares, minute dots, and the
          // hands, all Rectangles (no Canvas), driven by a seconds clock that
          // only runs while the sheet is open.
          Item {
            id: face
            readonly property real side: Math.min(root.du(90), root.dv(90))
            readonly property var now: vistaTick.date
            readonly property real r: side / 2
            x: root.du(144) + (root.du(90) - side) / 2
            y: root.dv(13) + (root.dv(90) - side) / 2
            width: side
            height: side

            Repeater {
              model: 60
              Rectangle {
                required property int index
                readonly property bool hour: index % 5 === 0
                readonly property real a: index * Math.PI / 30
                width: hour ? root.s(5) : root.s(2)
                height: width
                x: face.r + Math.sin(a) * (face.r - root.s(4)) - width / 2
                y: face.r - Math.cos(a) * (face.r - root.s(4)) - height / 2
                color: hour ? VistaScheme.sc.highlight : "#716F64"
                border.width: hour ? 1 : 0
                border.color: "#000000"
              }
            }
            Hand {
              width: root.s(5)
              length: face.r * 0.5
              color: "#4D6185"
              border.width: 1
              border.color: "#000000"
              angle: ((face.now.getHours() % 12) + face.now.getMinutes() / 60) * 30
            }
            Hand {
              width: root.s(4)
              length: face.r * 0.78
              color: "#4D6185"
              border.width: 1
              border.color: "#000000"
              angle: (face.now.getMinutes() + face.now.getSeconds() / 60) * 6
            }
            Hand {
              width: 1
              length: face.r * 0.82
              color: "#000000"
              angle: face.now.getSeconds() * 6
            }
          }
          // Setting the time needs root: shown, never enabled.
          VistaTextField {
            x: root.du(159); y: root.dv(105); width: root.du(57); height: root.dv(12)
            enabled: false
            text: Qt.formatTime(vistaTick.date, "h:mm:ss AP")
          }
          VistaSpin { x: root.du(217); y: root.dv(105); width: root.du(7); height: root.dv(12); enabled: false }

          VistaLabel {
            x: root.du(4); y: root.dv(136); width: root.du(243)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: "Current time zone:  " + root.tzLabel
          }
        }

        // -- Time Zone (template 2), read-only --
        Item {
          parent: sheet.page
          anchors.fill: parent
          visible: root.sheetTab === 1

          VistaComboBox {
            x: root.du(5); y: root.dv(4); width: root.du(241)
            enabled: false
            model: [root.tzLabel]
            currentIndex: 0
            MouseArea { id: tzMouse; anchors.fill: parent; hoverEnabled: true }
            VistaToolTip {
              visible: tzMouse.containsMouse
              y: parent.height + root.s(4)
              z: 20
              text: "Middle-click the taskbar clock to change the time zone."
            }
          }
          Image {
            x: root.du(5); y: root.dv(22); width: root.du(241); height: root.dv(113)
            // timedate.cpl's map, painted sea and land by vista-taskbar-art.
            source: VistaScheme.artRoot + "/tzmap.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
          }
          VistaCheckBox {
            x: root.du(5); y: root.dv(139)
            text: "A<u>u</u>tomatically adjust clock for daylight saving changes"
            checked: true
            enabled: false
          }
        }

        // -- Internet Time (template 3), read-only, from timedatectl --
        Item {
          id: netTimePage
          parent: sheet.page
          anchors.fill: parent
          visible: root.sheetTab === 2
          readonly property string server: root.tdInfo.ServerName || ""

          VistaCheckBox {
            x: root.du(8); y: root.dv(10)
            text: "Automatically <u>s</u>ynchronize with an Internet time server"
            checked: root.tdInfo.NTP === "yes"
            enabled: false
          }
          VistaLabel { x: root.du(31); y: root.dv(26); text: "Server:"; enabled: false }
          VistaComboBox {
            x: root.du(60); y: root.dv(24); width: root.du(115)
            enabled: false
            model: [netTimePage.server || "(none)"]
            currentIndex: 0
          }
          VistaButton { x: root.du(180); y: root.dv(24); width: root.du(55); height: root.dv(14); text: "<u>U</u>pdate Now"; enabled: false }
          VistaLabel {
            x: root.du(8); y: root.dv(52); width: root.du(235)
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.tdInfo.NTPSynchronized === "yes"
              ? "The time has been successfully synchronized" + (netTimePage.server ? " with " + netTimePage.server : "") + "."
              : root.tdInfo.NTP === "yes" ? "Windows is waiting to synchronize with an Internet time server."
              : "Windows has never attempted to synchronize with an internet time server."
          }
          VistaLabel {
            x: root.du(8); y: root.dv(120); width: root.du(235)
            wrapMode: Text.WordWrap
            text: "Synchronization can occur only when your computer is connected to the Internet."
          }
        }

        // -- Calendar: stock's year progress and Memento Mori --
        Item {
          parent: sheet.page
          anchors.fill: parent
          visible: root.sheetTab === 3

          VistaGroupBox { x: root.du(7); y: root.dv(7); width: root.du(238); height: root.dv(58); caption: "This year" }
          VistaLabel {
            x: root.du(17); y: root.dv(21)
            text: root.today.getFullYear() + " is " + root.yearDonePercent + "% done."
          }
          VistaProgress {
            x: root.du(17); y: root.dv(33); width: root.du(218); height: root.s(18)
            value: root.yearDone
            MouseArea { anchors.fill: parent; onDoubleClicked: root.startEditingLife() }
          }
          VistaLabel {
            x: root.du(17); y: root.dv(50)
            enabled: false
            text: root.editingLife ? "Enter saves, Esc cancels, Tab moves between the boxes."
                  : "Double-click the bar to set up Memento Mori."
          }

          VistaGroupBox {
            visible: root.editingLife || root.birthYear > 0
            x: root.du(7); y: root.dv(71); width: root.du(238); height: root.dv(58)
            caption: "Memento Mori"
          }
          Row {
            visible: root.editingLife
            x: root.du(17); y: root.dv(85)
            spacing: root.s(8)
            VistaLabel { anchors.verticalCenter: parent.verticalCenter; text: "Born:" }
            VistaTextField {
              id: bornBox
              width: root.s(70); height: root.s(21)
              input.Keys.onPressed: function(e) { root.handleLifeKey(e, lifeBox.input) }
            }
            VistaLabel { anchors.verticalCenter: parent.verticalCenter; text: "Live to:" }
            VistaTextField {
              id: lifeBox
              width: root.s(50); height: root.s(21)
              input.Keys.onPressed: function(e) { root.handleLifeKey(e, bornBox.input) }
            }
          }
          VistaLabel {
            visible: !root.editingLife && root.birthYear > 0
            x: root.du(17); y: root.dv(85)
            text: "Life: " + root.lifeDonePercent + "% (age " + root.age + " of " + root.lifeExpectancy + ")"
          }
          VistaProgress {
            visible: !root.editingLife && root.birthYear > 0
            x: root.du(17); y: root.dv(97); width: root.du(218); height: root.s(18)
            value: root.lifeDone
            MouseArea { anchors.fill: parent; onDoubleClicked: root.clearLife() }
          }

          VistaCheckBox {
            x: root.du(7); y: root.dv(137)
            text: "Start weeks on Monday"
            checked: root.weekStart === Qt.Monday
            onToggled: root.toggleWeekStart()
          }
        }
      }
    }
  }
}
