import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Commons as Commons
import "../../vista/qml"

// The agents dashboard as a Vista property sheet, over the stock 4.5 agents
// panel's model. `host` is the panel (ocko.vista-agents Panel.qml); `usage` is
// its Main.
//
// One tab per subscription (host.providers), then a Summary tab. Adding or
// re-signing a subscription (host.addStage), or a machine with nothing set up
// yet (host.blankSlate), turns the sheet into a single "Add" page.
//
// host reads:  providers, providerIndex, provider, limits, models, balance,
//   addStage, addProviders, addChecks, addStatus, addCode, addUrl,
//   addNeedsPaste, addResult, addHeading, addButtonShown, blankSlate,
//   picking, summaryPhrases, starterPrompts, renaming (written)
// host calls: selectProvider, refreshNow, launchAgent, close, heroMeta,
//   resetMsFor, formatDuration, formatMoney, balanceAlarming,
//   balanceDetailText, dayLabel, dayTooltip, weekPeak, todayDate,
//   modelTooltip, footerText, iconCandidatesForProvider, windowDisplayTitle,
//   scopedAllowanceText, resetCreditsText, providerAccounts, accountDetail,
//   needsSignIn, usageNote, statusDisplayText, helpDisplayText, signInAgain,
//   useAccount, renameAccount, autoSwitchFor, switchThreshold, setSwitchMode,
//   displayWindows, addAccount, cancelAdd, chooseAddProvider, startAdd,
//   submitPaste, reopenSignIn, startPrompt, focusKeys
// usage calls: formatTokenCount
Item {
  id: view

  required property var host
  property var usage: null
  property real maxHeight: 0
  // The root resets panelFlick.contentY on open; this is the page's Flickable's.
  property alias contentY: flick.contentY

  // ---- which page ----
  readonly property bool adding: host.addStage !== "" || host.blankSlate
  property bool onSummary: false
  readonly property bool showSummary: !adding && (onSummary || host.providers.length === 0)
  readonly property var p: adding || showSummary ? null : host.provider
  readonly property var accounts: p ? host.providerAccounts(p) : []
  readonly property bool multi: accounts.length > 1

  // An inline edit has the keyboard; the panel's key catcher stands aside.
  property string renameKey: ""
  readonly property bool editing: renameKey !== "" || addNameField.input.activeFocus || pasteField.input.activeFocus
  onRenameKeyChanged: host.renaming = renameKey !== ""

  readonly property var days: p ? (p.recentDays || []) : []
  readonly property real dayPeak: Math.max(1, host.weekPeak(p))
  readonly property var models: p ? host.models : []
  readonly property var balance: p ? host.balance : null
  readonly property real balanceRatio: balance && balance.funded > 0
    ? Math.max(0, Math.min(1, balance.remaining / balance.funded)) : -1
  // Vista draws a warning in red text; the progress chunks have no alarm colour.
  readonly property color alarmText: "#FF0000"

  function s(n) { return Style.space(n) }
  function du(x) { return Style.space(Math.round(x * 1.5)) }
  function dv(y) { return Style.space(Math.round(y * 13 / 8)) }
  function tokens(n) { return view.usage ? view.usage.formatTokenCount(Number(n || 0)) : String(n || 0) }
  // A VistaGroupBox's height around a column: caption, gap, content, inset.
  function boxHeight(c) { return fm.height + s(6) + c.implicitHeight + s(9) }

  function scrollBy(dy) {
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + dy))
  }

  // Tabs: every subscription, then Summary. h/l and the tab strip walk them.
  function selectTab(i) {
    if (i >= host.providers.length) {
      onSummary = true
    } else {
      onSummary = false
      host.selectProvider(i)
    }
    flick.contentY = 0
  }
  function step(dx) {
    var n = host.providers.length + 1
    var cur = showSummary ? n - 1 : host.providerIndex
    selectTab(((cur + dx) % n + n) % n)
  }

  // "Last updated ..." under numbers kept past a failed check (4.5's tooltip).
  function staleText(stale, fetchedAt) {
    if (!stale) return ""
    var now = host.nowMs
    return fetchedAt > 0 && now - fetchedAt > 60000
      ? Commons.I18n.t("agents.lastUpdatedAgo").arg(host.formatDuration(now - fetchedAt))
      : fetchedAt > 0 ? Commons.I18n.t("agents.lastUpdatedJustNow") : Commons.I18n.t("agents.lastUpdatedUnknown")
  }

  // A limit window's note: when it resets, its scoped (per-model) allowances,
  // and the age of numbers that are not current.
  function windowNote(w, stale, fetchedAt) {
    var lines = []
    var ms = host.resetMsFor(w)
    if (ms > 0) lines.push("Resets in " + host.formatDuration(ms))
    var scoped = w && w.scoped ? w.scoped : []
    for (var i = 0; i < scoped.length; i++) lines.push(host.scopedAllowanceText(scoped[i], w.title))
    var old = staleText(stale, fetchedAt)
    if (old !== "") lines.push(old)
    return lines.join("\n")
  }

  // Why the numbers are not current, said in full: the status, then its help.
  function troubleText(item) {
    if (!item) return ""
    var status = host.statusDisplayText(item.usageStatusText)
    var help = host.helpDisplayText(item.authHelpText)
    return status !== "" && help !== "" && help !== status ? status + "\n" + help : (help || status)
  }

  function finishRename(account, text, save) {
    var value = String(text || "").trim()
    var label = String(account.label || account.id || "")
    renameKey = ""
    host.focusKeys()
    if (save && value !== "" && value !== label) host.renameAccount(view.p, account, value)
  }

  // One tooltip for the whole sheet, so the scrolling page never clips it.
  property Item tipOwner: null
  property string tipText: ""
  function showTip(item, text) {
    var pt = item.mapToItem(view, 0, item.height + s(2))
    tip.x = Math.max(0, Math.min(view.width - tip.width, pt.x))
    tip.y = pt.y
    tipText = text
    tipOwner = item
  }
  function hideTip(item) { if (tipOwner === item) tipOwner = null }

  // VistaTabs insets its page by 2 * s(2) inside a pane s(4) taller than the
  // page, which rounds 1 px short at this rem; ask for that much more.
  readonly property real pageNaturalHeight: Math.ceil(col.implicitHeight + 2 * dv(7) + bottomRow.height + dv(7)
    + 2 * s(2) - s(4))
  readonly property real sheetChrome: sheet.captionHeight + s(6) + s(21) + s(4) + s(6 + 23 + 6) + sheet.frameWidth

  width: sheet.width
  height: sheet.height

  FontMetrics {
    id: fm
    font.family: "Segoe UI"
    font.pixelSize: Style.font.bodySmall
  }

  // A labelled meter: title left, value right, Vista progress bar, note under.
  component Meter: Column {
    id: meter
    property string title: ""
    property string valueText: ""
    property bool alarming: false
    property real value: -1
    property string note: ""
    spacing: view.dv(2)
    Item {
      width: meter.width
      height: fm.height
      VistaLabel {
        width: parent.width - meterValue.implicitWidth - view.s(8)
        text: meter.title
        textFormat: Text.PlainText
        elide: Text.ElideRight
      }
      VistaLabel {
        id: meterValue
        anchors.right: parent.right
        text: meter.valueText
        textFormat: Text.PlainText
        color: meter.alarming ? view.alarmText : "#000000"
      }
    }
    VistaProgress {
      visible: meter.value >= 0
      width: meter.width
      height: view.s(18)
      value: meter.value
    }
    VistaLabel {
      visible: text !== ""
      width: meter.width
      text: meter.note
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
    }
  }

  // One limit window as a Meter (4.5's CompactLimit, spelled out).
  component LimitMeter: Meter {
    property var window: null
    property bool stale: false
    property real fetchedAt: 0
    title: window ? view.host.windowDisplayTitle(window.title) + ":" : ""
    valueText: window && window.percent >= 0 ? Math.round(window.percent * 100) + "%" : "—"
    alarming: !!window && window.percent >= 0.9
    value: window ? window.percent : -1
    note: view.windowNote(window, stale, fetchedAt)
  }

  // A warning line: the Vista warning icon, the text, and an optional button.
  component WarningLine: Row {
    id: warn
    property string text: ""
    property string buttonText: ""
    signal buttonClicked()
    visible: text !== ""
    spacing: view.du(7)
    Image {
      width: view.s(32)
      height: view.s(32)
      source: VistaScheme.sysIcon("warning", 32)
      smooth: true
    }
    Column {
      width: warn.width - view.s(32) - view.du(7)
      anchors.verticalCenter: parent.verticalCenter
      spacing: view.dv(4)
      VistaLabel {
        width: parent.width
        text: warn.text
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
      }
      VistaButton {
        visible: warn.buttonText !== ""
        width: Math.max(view.s(75), Math.ceil(fm.advanceWidth(text)) + view.s(16))
        text: warn.buttonText
        onClicked: warn.buttonClicked()
      }
    }
  }

  // The stock mark, walking its candidates; the Microsoft Agent icon (the
  // tray art) when the provider ships none.
  component Mark: Item {
    id: mark
    property var provider: view.p
    // sc.face is a string in VistaScheme's table; stock's luminance test reads
    // .r/.g/.b, so hand it a color.
    readonly property var allCandidates: mark.provider ? view.host.iconCandidatesForProvider(mark.provider, Qt.color(VistaScheme.sc.face)) : []
    // On a light face stock tries assets/<id>-light.svg first, and a missing
    // twin logs "Cannot open" on every open; load only files that exist.
    FolderListModel {
      id: markFiles
      folder: mark.allCandidates.length ? String(mark.allCandidates[0]).replace(/[^\/]*$/, "") : ""
      nameFilters: ["*.svg"]
      showDirs: false
    }
    readonly property var candidates: {
      var have = []
      for (var i = 0; i < markFiles.count; i++) have.push(markFiles.get(i, "fileName"))
      return allCandidates.filter(function(u) { return have.indexOf(String(u).replace(/^.*\//, "")) !== -1 })
    }
    property string candidatesKey: candidates.join("\n")
    property int candidateIndex: 0
    onCandidatesKeyChanged: candidateIndex = 0
    width: view.s(32)
    height: view.s(32)
    Image {
      id: markImage
      anchors.fill: parent
      source: mark.candidateIndex < mark.candidates.length ? mark.candidates[mark.candidateIndex] : ""
      sourceSize.width: mark.width * 2
      sourceSize.height: mark.height * 2
      fillMode: Image.PreserveAspectFit
      onStatusChanged: if (status === Image.Error && mark.candidateIndex < mark.candidates.length)
        Qt.callLater(function() { mark.candidateIndex++ })
    }
    Image {
      anchors.fill: parent
      visible: markImage.status !== Image.Ready
      source: VistaScheme.graphics + "/agentsvr/32/113.png"
      smooth: true
    }
  }

  VistaPropertySheet {
    id: sheet
    title: "Agents"
    titleIcon: VistaScheme.graphics + "/agentsvr/16/113.png"
    buttons: ["close"]
    onCloseClicked: view.host.close()
    titles: view.adding ? [view.host.addHeading]
      : view.host.providers.map(function(q) { return q.providerName }).concat(["Summary"])
    tab: view.adding ? 0 : view.showSummary ? view.host.providers.length : view.host.providerIndex
    onTabClicked: function(i) { if (!view.adding) view.selectTab(i) }
    pageWidth: view.du(252)
    pageHeight: view.maxHeight > 0
      ? Math.min(view.pageNaturalHeight, view.maxHeight - view.sheetChrome) : view.pageNaturalHeight
    buttonLabels: ["Close"]
    defaultButton: -1
    onButtonClicked: view.host.close()

    Item {
      parent: sheet.page
      anchors.fill: parent

      Flickable {
        id: flick
        width: parent.width - (scroll.visible ? scroll.width : 0)
        // Ends a gap and an etched rule above the button row, so content
        // scrolls under neither (Vista separated a sheet's button row so).
        height: parent.height - bottomRow.height - 3 * view.dv(7)
        contentWidth: width
        contentHeight: col.implicitHeight + 2 * view.dv(7)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: col
          x: view.du(7)
          y: view.dv(7)
          width: flick.width - 2 * view.du(7)
          spacing: view.dv(6)

          // =========================== a subscription ===========================

          // ---- the subscription: mark, tool, plan ----
          Item {
            visible: !!view.p
            width: col.width
            height: Math.max(view.s(32), heroText.implicitHeight)
            Mark { id: heroMark }
            Column {
              id: heroText
              x: heroMark.width + view.du(10)
              width: parent.width - x
              anchors.verticalCenter: parent.verticalCenter
              VistaLabel {
                width: parent.width
                text: view.p ? view.p.providerName : ""
                textFormat: Text.PlainText
                font.bold: true
                elide: Text.ElideRight
              }
              VistaLabel {
                width: parent.width
                text: view.host.heroMeta(view.p)
                textFormat: Text.PlainText
                elide: Text.ElideRight
              }
            }
          }
          VistaEtched { visible: !!view.p; width: col.width }

          // ---- a lapsed sign-in (single account), with the way to fix it ----
          WarningLine {
            width: col.width
            text: view.p && !view.multi && view.host.needsSignIn(view.p) ? view.troubleText(view.p) : ""
            buttonText: "Sign In..."
            onButtonClicked: view.host.signInAgain(view.p, null)
          }

          // ---- any other reason the numbers are not current ----
          WarningLine {
            width: col.width
            text: view.p && !view.multi ? view.host.usageNote(view.p) : ""
          }

          // ---- balance ----
          VistaGroupBox {
            visible: !!view.balance
            width: col.width
            height: view.boxHeight(balanceCol)
            caption: "Balance"
            Column {
              id: balanceCol
              width: parent.width
              Meter {
                width: parent.width
                title: "Prepaid credits:"
                valueText: view.balance ? view.host.formatMoney(view.balance.remaining, view.balance.currency) : ""
                alarming: view.host.balanceAlarming(view.balance)
                value: view.balanceRatio
                note: view.host.balanceDetailText(view.balance)
              }
            }
          }

          // ---- limits (single account) ----
          VistaGroupBox {
            visible: !!view.p && !view.multi && (view.host.limits.length > 0 || resetCredits.text !== "")
            width: col.width
            height: view.boxHeight(limitsCol)
            caption: "Limits"
            Column {
              id: limitsCol
              width: parent.width
              spacing: view.dv(6)
              Repeater {
                model: view.p && !view.multi ? view.host.limits : []
                LimitMeter {
                  required property var modelData
                  width: limitsCol.width
                  window: modelData
                  stale: !!view.p && view.p.limitsStale === true
                  fetchedAt: view.p ? Number(view.p.limitsFetchedAt || 0) : 0
                }
              }
              // Codex's free resets.
              VistaLabel {
                id: resetCredits
                visible: text !== ""
                width: parent.width
                text: view.p ? view.host.resetCreditsText(view.p.resetCredits) : ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
              }
            }
          }

          // ---- accounts (several): who new sessions use, and each one's limits ----
          VistaGroupBox {
            visible: view.multi
            width: col.width
            height: view.boxHeight(accountsCol)
            caption: "Accounts"
            Column {
              id: accountsCol
              width: parent.width
              spacing: view.dv(6)

              VistaCheckBox {
                text: "Switch accounts automatically at " + view.host.switchThreshold(view.p) + "%"
                checked: view.host.autoSwitchFor(view.p)
                onToggled: view.host.setSwitchMode(view.p, view.host.autoSwitchFor(view.p) ? "manual" : "auto")
              }

              Repeater {
                model: view.multi ? view.accounts : []

                Column {
                  id: acct
                  required property var modelData
                  required property int index
                  readonly property string key: String(modelData.id)
                  readonly property string label: String(modelData.label || modelData.id || "")
                  readonly property bool isActive: modelData.active === true
                  width: accountsCol.width
                  spacing: view.dv(3)

                  VistaEtched { visible: acct.index > 0; width: acct.width }

                  // Name (click to rename), plan and caveats; Active or Use.
                  Item {
                    width: acct.width
                    height: Math.max(view.s(23), nameText.implicitHeight)
                    VistaLabel {
                      id: nameText
                      visible: view.renameKey !== acct.key
                      width: Math.min(implicitWidth, parent.width * 0.45)
                      anchors.verticalCenter: parent.verticalCenter
                      text: acct.label
                      textFormat: Text.PlainText
                      font.bold: acct.isActive
                      font.underline: nameMouse.containsMouse
                      elide: Text.ElideRight
                      MouseArea {
                        id: nameMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.IBeamCursor
                        onClicked: view.renameKey = acct.key
                        onContainsMouseChanged: containsMouse && String(acct.modelData.email || "") !== ""
                          ? view.showTip(nameText, String(acct.modelData.email)) : view.hideTip(nameText)
                      }
                    }
                    VistaTextField {
                      id: nameField
                      visible: view.renameKey === acct.key
                      width: parent.width * 0.6
                      anchors.verticalCenter: parent.verticalCenter
                      onVisibleChanged: if (visible) {
                        text = acct.label
                        input.forceActiveFocus()
                        input.selectAll()
                      }
                      Connections {
                        target: nameField.input
                        function onAccepted() { view.finishRename(acct.modelData, nameField.text, true) }
                        function onActiveFocusChanged() {
                          if (!nameField.input.activeFocus && view.renameKey === acct.key) view.finishRename(acct.modelData, "", false)
                        }
                      }
                      Keys.onEscapePressed: function(event) {
                        view.finishRename(acct.modelData, "", false)
                        event.accepted = true
                      }
                    }
                    VistaLabel {
                      visible: nameText.visible && text !== ""
                      anchors.left: nameText.right
                      anchors.leftMargin: view.s(6)
                      anchors.right: acctAction.left
                      anchors.rightMargin: view.s(6)
                      anchors.verticalCenter: parent.verticalCenter
                      text: view.host.accountDetail(acct.modelData)
                      textFormat: Text.PlainText
                      color: VistaScheme.sc.gray
                      elide: Text.ElideRight
                    }
                    VistaLabel {
                      id: acctAction
                      visible: acct.isActive
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Active"
                      textFormat: Text.PlainText
                      font.bold: true
                    }
                    VistaButton {
                      visible: !acct.isActive
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Use"
                      onClicked: view.host.useAccount(view.p, acct.modelData)
                    }
                  }

                  WarningLine {
                    width: acct.width
                    text: view.host.needsSignIn(acct.modelData) ? view.troubleText(acct.modelData) : ""
                    buttonText: "Sign In..."
                    onButtonClicked: view.host.signInAgain(view.p, acct.modelData)
                  }
                  WarningLine {
                    width: acct.width
                    text: view.host.usageNote(acct.modelData)
                  }

                  Repeater {
                    model: view.host.displayWindows({ limits: acct.modelData.limits || [] })
                    LimitMeter {
                      required property var modelData
                      width: acct.width
                      window: modelData
                      stale: acct.modelData.stale === true
                      fetchedAt: Number(acct.modelData.fetchedAt || 0)
                    }
                  }
                }
              }
            }
          }

          // ---- tokens by day: day, bar scaled to the busiest day, tokens ----
          VistaGroupBox {
            visible: view.days.length > 0
            width: col.width
            height: view.boxHeight(daysCol)
            caption: "Tokens by day"
            Column {
              id: daysCol
              width: parent.width
              spacing: view.dv(2)
              Repeater {
                model: view.days
                Item {
                  id: dayRow
                  required property var modelData
                  // By date, not by position (stock's rule).
                  readonly property bool today: String(modelData.date || "") === view.host.todayDate()
                  width: daysCol.width
                  height: view.s(16)
                  VistaLabel {
                    id: dayName
                    width: view.du(30)
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.host.dayLabel(dayRow.modelData.date, dayRow.today)
                    textFormat: Text.PlainText
                    font.bold: dayRow.today
                  }
                  VistaProgress {
                    x: dayName.width
                    width: parent.width - dayName.width - dayValue.width - view.du(4)
                    height: view.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    value: Number(dayRow.modelData.messageCount || 0) / view.dayPeak
                  }
                  VistaLabel {
                    id: dayValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: view.du(34)
                    horizontalAlignment: Text.AlignRight
                    text: view.tokens(dayRow.modelData.messageCount)
                    textFormat: Text.PlainText
                    font.bold: dayRow.today
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onContainsMouseChanged: containsMouse
                      ? view.showTip(dayRow, view.host.dayTooltip(dayRow.modelData, dayRow.today))
                      : view.hideTip(dayRow)
                  }
                }
              }
            }
          }

          // ---- tokens by model: a report-view list, scaled to the top model ----
          VistaLabel {
            visible: view.models.length > 0
            text: "Tokens by model:"
            textFormat: Text.PlainText
          }
          VistaListView {
            id: modelList
            visible: view.models.length > 0
            width: col.width
            height: headerHeight + rowHeight * view.models.length + 2
            columns: [{ title: "Model", width: 190 }, { title: "Tokens", width: 80 }, { title: "Relative", width: 60 }]
            rows: view.models.map(function(r) {
              return [r.name, view.tokens(r.total), Math.round(100 * r.total / Math.max(1, view.models[0].total)) + "%"]
            })
            MouseArea {
              id: modelHover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              readonly property int row: containsMouse
                ? Math.floor((mouseY - modelList.headerHeight - 1) / modelList.rowHeight) : -1
              onRowChanged: {
                var r = view.models[row]
                if (row >= 0 && r) view.showTip(modelList, view.host.modelTooltip(r))
                else view.hideTip(modelList)
              }
            }
          }

          // =========================== Summary tab ===========================
          // 4.5's rotating hero line, every phrase at once.
          VistaGroupBox {
            visible: view.showSummary
            width: col.width
            height: view.boxHeight(summaryCol)
            caption: "Summary"
            Column {
              id: summaryCol
              width: parent.width
              spacing: view.dv(2)
              Repeater {
                model: view.showSummary ? view.host.summaryPhrases : []
                VistaLabel {
                  required property var modelData
                  width: summaryCol.width
                  text: String(modelData)
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                }
              }
              VistaLabel {
                visible: view.host.summaryPhrases.length === 0
                width: parent.width
                text: "No usage recorded yet."
                textFormat: Text.PlainText
              }
            }
          }

          // 4.5's starter prompts, handed to the default agent.
          VistaGroupBox {
            visible: view.showSummary
            width: col.width
            height: view.boxHeight(makeCol)
            caption: "Make something"
            Column {
              id: makeCol
              width: parent.width
              spacing: view.dv(4)
              VistaLabel {
                width: parent.width
                text: Commons.I18n.t("agents.startOnNew").arg("…")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
              }
              Row {
                spacing: view.s(6)
                Repeater {
                  model: view.showSummary ? view.host.starterPrompts : []
                  VistaButton {
                    required property var modelData
                    text: String(modelData.label)
                    onClicked: view.host.startPrompt(modelData.prompt)
                  }
                }
              }
            }
          }

          // =========================== Add page ===========================
          // 4.5's AddView: pick, name, sign in, done.
          VistaLabel {
            visible: view.adding && view.host.blankSlate && view.host.picking
            width: col.width
            text: Commons.I18n.t("agents.signInIntro")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
          }

          VistaGroupBox {
            visible: view.adding && view.host.picking
            width: col.width
            height: view.boxHeight(pickCol)
            caption: "Choose a subscription"
            Column {
              id: pickCol
              width: parent.width
              spacing: view.dv(4)
              Repeater {
                model: view.adding && view.host.picking ? view.host.addProviders : []
                Item {
                  id: choice
                  required property var modelData
                  readonly property string state: view.host.addChecks[modelData.providerId] || ""
                  width: pickCol.width
                  height: view.s(32)
                  Mark { id: choiceMark; provider: choice.modelData }
                  VistaLabel {
                    x: choiceMark.width + view.du(7)
                    anchors.verticalCenter: parent.verticalCenter
                    text: choice.modelData.providerName
                    textFormat: Text.PlainText
                    font.bold: true
                  }
                  VistaButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: choice.state === "first" || choice.state === "additional"
                    text: choice.state === "additional" ? "Add..." : "Sign In..."
                    onClicked: view.host.chooseAddProvider(choice.modelData.providerId)
                  }
                }
              }
            }
          }

          // Name: a second account needs telling apart from the first.
          Column {
            visible: view.adding && view.host.addStage === "name"
            width: col.width
            spacing: view.dv(4)
            VistaLabel {
              width: parent.width
              text: Commons.I18n.t("agents.nameAccount")
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
            }
            Row {
              spacing: view.s(6)
              VistaTextField {
                id: addNameField
                width: col.width - view.s(75 + 6)
                placeholder: Commons.I18n.t("agents.placeholderWork")
                onVisibleChanged: if (visible) { text = ""; input.forceActiveFocus() }
                Connections {
                  target: addNameField.input
                  function onAccepted() { view.host.startAdd(addNameField.text.trim()) }
                }
                Keys.onEscapePressed: function(event) { view.host.cancelAdd(); event.accepted = true }
              }
              VistaButton {
                text: "OK"
                isDefault: true
                onClicked: view.host.startAdd(addNameField.text.trim())
              }
            }
          }

          // Running: what's happening, and whatever the sign-in needs from you.
          Column {
            visible: view.adding && view.host.addStage === "running"
            width: col.width
            spacing: view.dv(6)
            VistaLabel {
              width: parent.width
              text: view.host.addStatus
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
            }
            VistaLabel {
              visible: view.host.addCode !== ""
              text: Commons.I18n.t("agents.confirmCode")
              textFormat: Text.PlainText
            }
            VistaLabel {
              visible: view.host.addCode !== ""
              text: view.host.addCode
              textFormat: Text.PlainText
              font.bold: true
              font.pixelSize: Style.font.heading
              font.letterSpacing: 2
            }
            VistaLabel {
              visible: view.host.addNeedsPaste
              width: parent.width
              text: Commons.I18n.t("agents.pasteCode")
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
            }
            Row {
              visible: view.host.addNeedsPaste
              spacing: view.s(6)
              VistaTextField {
                id: pasteField
                width: col.width - view.s(75 + 6)
                placeholder: Commons.I18n.t("agents.placeholderCode")
                Connections {
                  target: pasteField.input
                  function onAccepted() { view.host.submitPaste(pasteField.text); pasteField.text = "" }
                }
                Keys.onEscapePressed: function(event) { view.host.cancelAdd(); event.accepted = true }
              }
              VistaButton {
                text: "Submit"
                onClicked: { view.host.submitPaste(pasteField.text); pasteField.text = "" }
              }
            }
            VistaButton {
              visible: view.host.addUrl !== ""
              width: Math.max(view.s(75), Math.ceil(fm.advanceWidth(text)) + view.s(16))
              text: Commons.I18n.t("agents.reopenSignIn")
              onClicked: view.host.reopenSignIn()
            }
          }

          // Done or failed.
          VistaLabel {
            visible: view.adding && (view.host.addStage === "done" || view.host.addStage === "error")
            width: col.width
            text: view.host.addResult
            textFormat: Text.PlainText
            color: view.host.addStage === "error" ? view.alarmText : "#000000"
            wrapMode: Text.WordWrap
          }
        }
      }

      VistaScrollBar {
        id: scroll
        target: flick
        x: parent.width - width
        height: flick.height
      }

      VistaEtched {
        x: view.du(7)
        y: flick.height + view.dv(7)
        width: parent.width - 2 * view.du(7)
      }

      // ---- footer and the page's push buttons (Task Manager's place) ----
      Item {
        id: bottomRow
        x: view.du(7)
        y: parent.height - height - view.dv(7)
        width: parent.width - 2 * view.du(7)
        height: view.s(23)
        VistaLabel {
          anchors.left: parent.left
          anchors.right: pushButtons.left
          anchors.rightMargin: view.s(8)
          anchors.verticalCenter: parent.verticalCenter
          text: view.adding ? "" : view.host.footerText()
          textFormat: Text.PlainText
          elide: Text.ElideRight
        }
        Row {
          id: pushButtons
          anchors.right: parent.right
          spacing: view.s(6)
          // Adding: back to the limits (none on a first setup, as in stock).
          VistaButton {
            visible: view.adding && view.host.addButtonShown
            text: "Cancel"
            onClicked: view.host.cancelAdd()
          }
          VistaButton {
            visible: !view.adding
            text: "Add..."
            onClicked: view.host.addAccount()
          }
          VistaButton {
            visible: !view.adding
            width: view.s(100)
            text: "Launch Agent..."
            onClicked: view.host.launchAgent()
          }
          VistaButton {
            visible: !view.adding
            text: "<u>R</u>efresh"
            isDefault: true
            onClicked: view.host.refreshNow()
          }
        }
      }
    }
  }

  VistaToolTip {
    id: tip
    z: 50
    visible: view.tipOwner !== null && text !== ""
    text: view.tipText
  }
}
