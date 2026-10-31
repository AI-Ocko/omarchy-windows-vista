// ocko.vista-clock: omarchy.clock's calendar for the Vista notification area (Windows
// Vista theme only; see omarchy/vista/bin/vista-mode). Lines 9-250 are the logic of
// /usr/share/omarchy/shell/plugins/panels/clock/Panel.qml (Omarchy 4.0.6,
// sha256 ff6062b3a5714a727c345d239449d460c95e6087c99f4cda786942c33cdaa612,
// lines 1-240), with each change marked "Vista:". The card below that is
// Vista's clock flyout (timedate.cpl UIFILE 305).
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
  // Vista's clock flyout, as timedate.cpl's UIFILE 305 lays it out: the date
  // as a header link (Today; FlyoutStyle LINKHEADER, Segoe UI 12 pt #0066CC),
  // the month calendar (aero.msstyles MonthCal parts and colours) beside the
  // analog clock (timedate PNGFILE 5002/5004 face + 5003/5005 glass) with the
  // digital time under it, the Flyout divider, and the link area (#F0F0F0)
  // with "Change date and time settings..." (here: omarchy-menu-timezone).
  // Paddings are the UIFILE's: 14 rp round the header and calendar, 10 rp
  // between calendar and clock.
  // =========================================================================

  // Stock's commitLife/startEditingLife read these by name; the flyout has no
  // life fields (Vista had none), so they are inert.
  TextInput { id: bornField; visible: false }
  TextInput { id: expectancyField; visible: false }

  function s(n) { return Style.space(n) }
  readonly property string tdArt: "file://" + Quickshell.env("HOME") + "/.config/omarchy/vista/assets/graphics/timedate/PNGFILE/"
  readonly property string mcArt: "file://" + Quickshell.env("HOME") + "/.config/omarchy/vista/assets/graphics/aero/parts/MonthCal/"

  function vistaBareCard(item) {
    var card = item && item.parent ? item.parent.parent : null
    if (card && "radius" in card) {
      card.color = "transparent"
      card.radius = 0
    }
  }

  Process { id: tzMenu; command: ["omarchy-menu-timezone"] }

  // The analog clock ticks by the second, and only while the flyout is open.
  SystemClock {
    id: vistaTick
    precision: SystemClock.Seconds
    enabled: root.opened
  }

  // A clock hand: a bar from the centre of its parent, rotated about its base.
  component Hand: Rectangle {
    property real turn: 0
    property real length: 0
    property real tail: 0
    x: parent.width / 2 - width / 2
    y: parent.height / 2 - length
    height: length + tail
    antialiasing: true
    // about the centre of the face, which sits `length` down the bar
    transform: Rotation { origin.x: width / 2; origin.y: length; angle: turn }
  }

  component Link: Text {
    id: link
    signal clicked()
    color: "#0066CC"
    font.family: "Segoe UI"
    font.pixelSize: root.s(12)
    font.underline: linkMouse.containsMouse
    MouseArea {
      id: linkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }
  }

  // ---- the panel ------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    // Vista: over the clock, not centred on the bar
    centerOnBar: false
    focusTarget: keyCatcher
    padding: 0
    borderSpec: Border.none()
    contentWidth: flyout.width
    contentHeight: flyout.height

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
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
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      // The flyout window: white (Flyout WINDOW) in a 1 px frame.
      Rectangle {
        id: flyout
        width: col.width + 2
        height: col.height + 2
        color: "#FFFFFF"
        border.color: "#7A7A7A"
        radius: root.s(3)

        WheelHandler {
          onWheel: function(event) { root.moveMonth(event.angleDelta.y > 0 ? -1 : 1) }
        }

        Column {
          id: col
          x: 1; y: 1
          width: calRow.width + root.s(28)

          // Header: today's long date, a link back to today.
          Item {
            width: parent.width
            height: todayLink.height + root.s(14 + 10)
            Link {
              id: todayLink
              anchors.horizontalCenter: parent.horizontalCenter
              y: root.s(14)
              text: root.labelLocale.toString(root.today, "dddd, MMMM d, yyyy")
              onClicked: root.goToToday()
            }
          }

          Row {
            id: calRow
            x: root.s(14)
            spacing: root.s(10)

            // ---- the month calendar
            Column {
              id: cal
              width: root.s(7 * 25 + 4)
              spacing: 0

              // MonthCal BACKGROUND strip: prev / "October, 2026" / next.
              Item {
                width: parent.width
                height: root.s(22)
                Image {
                  x: 0; anchors.verticalCenter: parent.verticalCenter
                  width: root.s(16); height: root.s(16)
                  source: root.mcArt + "11.0.IMAGEFILE.png"
                  sourceClipRect: Qt.rect(0, (prevMouse.pressed ? 2 : prevMouse.containsMouse ? 1 : 0) * 16, 16, 16)
                  MouseArea { id: prevMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.moveMonth(-1) }
                }
                Text {
                  anchors.centerIn: parent
                  text: root.labelLocale.standaloneMonthName(root.viewMonth, Locale.LongFormat) + ", " + root.viewYear
                  color: "#000000"
                  font.family: "Segoe UI"
                  font.pixelSize: root.s(12)
                }
                Image {
                  anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                  width: root.s(16); height: root.s(16)
                  source: root.mcArt + "10.0.IMAGEFILE.png"
                  sourceClipRect: Qt.rect(0, (nextMouse.pressed ? 2 : nextMouse.containsMouse ? 1 : 0) * 16, 16, 16)
                  MouseArea { id: nextMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.moveMonth(1) }
                }
              }

              // Day names, then the COLHEADERSPLITTER line.
              Row {
                x: root.s(2)
                Repeater {
                  model: root.weekdays
                  Text {
                    required property var modelData
                    width: root.s(25); height: root.s(19)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: String(root.labelLocale.dayName(modelData, Locale.ShortFormat)).slice(0, 2)
                    color: "#000000"
                    font.family: "Segoe UI"
                    font.pixelSize: root.s(12)
                  }
                }
              }
              Rectangle { x: root.s(4); width: parent.width - root.s(8); height: 1; color: "#E3E3E3" }
              Item { width: 1; height: root.s(2) }

              // The grid: trailing days #646464 (MonthCal TRAILINGGRIDCELL),
              // today selected (GRIDCELLBACKGROUND 3) with the blue today
              // outline (5), hover in the hot frame (1).
              Repeater {
                model: root.weeks
                Row {
                  required property var modelData
                  x: root.s(2)
                  Repeater {
                    model: modelData.days
                    Item {
                      required property var modelData
                      width: root.s(25); height: root.s(17)
                      BorderImage {
                        anchors.fill: parent
                        visible: modelData.today || cellMouse.containsMouse
                        source: root.mcArt + (modelData.today ? "5.3.IMAGEFILE.png" : "5.1.IMAGEFILE.png")
                        border { left: 3; right: 3; top: 3; bottom: 3 }
                      }
                      BorderImage {
                        anchors.fill: parent
                        visible: modelData.today
                        source: root.mcArt + "5.5.IMAGEFILE.png"
                        border { left: 2; right: 2; top: 2; bottom: 2 }
                      }
                      Text {
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.inMonth ? "#000000" : "#646464"
                        font.family: "Segoe UI"
                        font.pixelSize: root.s(12)
                      }
                      MouseArea { id: cellMouse; anchors.fill: parent; hoverEnabled: true }
                    }
                  }
                }
              }
              Item { width: 1; height: root.s(10) }
            }

            // ---- the clock
            Column {
              id: clockPanel
              topPadding: root.s(4)
              spacing: root.s(4)

              Item {
                id: face
                width: root.s(103); height: root.s(103)
                readonly property var t: vistaTick.date
                Image {
                  anchors.fill: parent
                  source: root.tdArt + (face.width > 110 ? "5004.png" : "5002.png")
                  smooth: true; mipmap: true
                }
                Hand {
                  width: root.s(3); color: "#3C3C3C"; radius: width / 2
                  length: face.width * 0.26
                  turn: (face.t.getHours() % 12) * 30 + face.t.getMinutes() / 2
                }
                Hand {
                  width: root.s(2); color: "#3C3C3C"; radius: width / 2
                  length: face.width * 0.37
                  turn: face.t.getMinutes() * 6 + face.t.getSeconds() / 10
                }
                Hand {
                  width: Math.max(1, root.s(1)); color: "#C02020"
                  length: face.width * 0.39; tail: face.width * 0.08
                  turn: face.t.getSeconds() * 6
                }
                Rectangle {
                  anchors.centerIn: parent
                  width: root.s(5); height: width; radius: width / 2
                  color: "#3C3C3C"
                }
                Image {
                  anchors.fill: parent
                  source: root.tdArt + (face.width > 110 ? "5005.png" : "5003.png")
                  smooth: true; mipmap: true
                }
              }
              Text {
                width: face.width
                horizontalAlignment: Text.AlignHCenter
                text: root.labelLocale.toString(vistaTick.date, "h:mm:ss AP")
                color: "#000000"
                font.family: "Segoe UI"
                font.pixelSize: root.s(12)
              }
            }
          }

          // Divider (Flyout DIVIDER) and the link area.
          Image {
            width: parent.width; height: root.s(2)
            source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/vista/assets/graphics/aero/parts/Flyout/5.0.IMAGEFILE.png"
          }
          Rectangle {
            width: parent.width
            height: setLink.height + root.s(28)
            color: "#F0F0F0"
            radius: root.s(2)
            Link {
              id: setLink
              anchors.centerIn: parent
              text: "Change date and time settings..."
              onClicked: { root.close(); tzMenu.running = true }
            }
          }
        }
      }
    }
  }
}
