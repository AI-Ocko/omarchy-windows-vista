// ocko.vista-agents: omarchy.agents 4.5.0 for the Vista notification area
// (Windows Vista theme only; see omarchy/vista/bin/vista-mode). Everything up
// to the "Vista UI" banner is /usr/share/omarchy/shell/plugins/agents/Panel.qml
// (Omarchy 4.5.0, sha256 9e23f39a47f416fae9df00f8451c17d198d24026d107bd0fed20ec95fa7b4b94,
// lines 1-980) verbatim except one marked "Vista:" edit; the card below the
// banner is a Vista property sheet (VistaAgents.qml). Main.qml, Agent.qml and
// assets/ are stock 4.5.0, byte-identical.
// Re-diff against a newer Omarchy: diff <(sed -n 10,991p Panel.qml) <(sed -n 1,980p <stock>)

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  // Items inside the panel's lazily built content, null until it first
  // opens. Code inside the content reaches its own ids directly.
  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null
  readonly property Item hero: panel.loadedContent ? panel.loadedContent.hero : null
  readonly property Item column: panel.loadedContent ? panel.loadedContent.column : null
  readonly property Item providerSections: panel.loadedContent ? panel.loadedContent.providerSections : null

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Commons.Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Commons.Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Every subscription on one page, limits first: the question this panel
  // answers is how much room is left, and where.
  readonly property var providers: usage.subscribedProviders

  property bool cursorActive: false

  // Countdowns and "last updated" ages read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  // Every account of every provider that has more than one, in page order.
  // The keyboard picks one by its position; picking only looks, and Enter on
  // a picked account is what moves new sessions to it.
  readonly property var accountEntries: {
    var out = []
    for (var i = 0; i < providers.length; i++) {
      var list = providerAccounts(providers[i])
      if (list.length < 2) continue
      for (var j = 0; j < list.length; j++) out.push({ provider: providers[i], account: list[j] })
    }
    return out
  }
  readonly property var pickedEntry: keyTarget && ["account", "autoswitch", "signin"].indexOf(keyTarget.kind) >= 0
    ? accountEntries[keyTarget.index] || null
    : null

  // The keyboard walks everything on the page that does something, in
  // reading order, one row at a time: the hero's buttons, then each agent's
  // header, its Sign-in required link or switchable accounts, and the starter
  // tiles, or the agents to add while picking one. Up and down change rows, left and right move along one.
  // Hovering moves the same cursor, so only one thing is lit.
  readonly property var keyRows: {
    var rows = []
    var hero = []
    if (addButtonShown) hero.push({ kind: "add", index: 0 })
    if (addStage === "") hero.push({ kind: "launch", index: 0 })
    if (hero.length > 0) rows.push(hero)
    if (picking) {
      var choices = []
      for (var k = 0; k < addProviders.length; k++) choices.push({ kind: "choice", index: k })
      rows.push(choices)
    } else if (addStage === "") {
      // Accounts count in the same order as accountEntries. Only what can be
      // done is a stop: one that isn't active offers Autoswitch beside Use, a
      // lapsed sign-in comes first, and the active account with nothing to
      // fix is skipped.
      var entry = 0
      for (var p = 0; p < providers.length; p++) {
        // Every agent's header is a stop, so Ctrl+Up/Down can move it.
        rows.push([{ kind: "provider", index: p }])
        var accounts = providerAccounts(providers[p])
        if (accounts.length < 2) {
          if (needsSignIn(providers[p])) rows.push([{ kind: "providerSignin", index: p }])
          continue
        }
        for (var a = 0; a < accounts.length; a++, entry++) {
          var row = []
          if (needsSignIn(accounts[a])) row.push({ kind: "signin", index: entry })
          if (!accounts[a].active) {
            row.push({ kind: "autoswitch", index: entry })
            row.push({ kind: "account", index: entry })
          }
          if (row.length > 0) rows.push(row)
        }
      }
      if (!blankSlate) {
        var tiles = []
        for (var j = 0; j < starterPrompts.length; j++) tiles.push({ kind: "starter", index: j })
        rows.push(tiles)
      }
    }
    return rows
  }
  property int keyRow: 0
  property int keyColumn: 0
  readonly property var keyTarget: {
    if (!cursorActive || keyRow < 0 || keyRow >= keyRows.length) return null
    var row = keyRows[keyRow]
    return row[Math.min(keyColumn, row.length - 1)]
  }

  function hasKey(kind, index) {
    return !!keyTarget && keyTarget.kind === kind && keyTarget.index === (index || 0)
  }

  function pointAt(kind, index) {
    for (var r = 0; r < keyRows.length; r++) {
      for (var c = 0; c < keyRows[r].length; c++) {
        if (keyRows[r][c].kind === kind && keyRows[r][c].index === (index || 0)) {
          keyRow = r
          keyColumn = c
          cursorActive = true
          return
        }
      }
    }
  }

  // The first arrow only shows where the cursor is, as in the other panels.
  function moveKey(dx, dy) {
    if (keyRows.length === 0) return
    if (!cursorActive) {
      keyRow = clamp(keyRow, 0, keyRows.length - 1)
      keyColumn = 0
      cursorActive = true
      return
    }
    if (dy !== 0) {
      keyRow = clamp(keyRow + dy, 0, keyRows.length - 1)
      // Arriving on an account lands on Use; left reaches Autoswitch.
      var row = keyRows[keyRow]
      var use = -1
      for (var c = 0; c < row.length; c++) if (row[c].kind === "account") use = c
      keyColumn = use >= 0 ? use : Math.min(keyColumn, row.length - 1)
    } else if (dx !== 0) {
      keyColumn = clamp(Math.min(keyColumn, keyRows[keyRow].length - 1) + dx, 0, keyRows[keyRow].length - 1)
    }
  }

  // The agent the cursor is in, by its position on the page.
  function providerIndexOfKey() {
    var target = keyTarget
    if (!target) return -1
    if (target.kind === "provider" || target.kind === "providerSignin") return target.index
    if (["account", "autoswitch", "signin"].indexOf(target.kind) < 0) return -1
    var entry = accountEntries[target.index]
    return entry ? providers.indexOf(entry.provider) : -1
  }

  // Ctrl+Up/Down carries the agent the cursor is in up or down the page, and
  // the cursor along with it.
  function reorderProvider(dy) {
    var from = providerIndexOfKey()
    if (from < 0) return
    var to = clamp(from + dy, 0, providers.length - 1)
    if (to === from) return
    usage.moveProvider(providers[from].providerId, to)
    Qt.callLater(function() { pointAt("provider", to) })
  }

  // Dragging an agent by its mark lights the header it would land on, and
  // moves it there on release: the sections are rebuilt when the order
  // changes, which would drop a drag still in progress.
  property string dragProviderId: ""
  property int dragTarget: -1
  // An account name being edited keeps Ctrl+Up/Down: moving its agent would
  // rebuild the section and drop the unfinished name.
  property bool renaming: false

  function dragProviderOver(y) {
    if (!providerSections) return
    for (var i = 0; i < providerSections.count; i++) {
      var item = providerSections.itemAt(i)
      if (item && y >= item.y && y < item.y + item.height) {
        dragTarget = i
        return
      }
    }
  }

  function dropProvider() {
    var id = dragProviderId
    var to = dragTarget
    dragProviderId = ""
    dragTarget = -1
    if (id === "" || to < 0) return
    usage.moveProvider(id, to)
    Qt.callLater(function() { pointAt("provider", to) })
  }

  // Keeps whatever the cursor lands on inside the scrolled view.
  function revealItem(item) {
    if (!item || !column || !panelFlick || !panelFlick.interactive) return
    var top = item.mapToItem(column, 0, 0).y
    var margin = Style.space(12)
    if (top - margin < panelFlick.contentY)
      panelFlick.contentY = Math.max(0, top - margin)
    else if (top + item.height + margin > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height, top + item.height + margin - panelFlick.height)
  }

  // The bar icon lights up when any account new sessions use is nearly out,
  // or a prepaid balance is down to its last 10%.
  readonly property bool alarming: {
    for (var i = 0; i < providers.length; i++) {
      var window = bindingWindow(providers[i])
      if (window && window.percent >= 0.9) return true
      if (balanceAlarming(providers[i].balance)) return true
    }
    return false
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // A provider's accounts, when it has any. The list arrives as a sequence
  // rather than a JS array once it has passed through a model, so it's
  // judged by its length.
  function providerAccounts(p) {
    return p && p.accounts && p.accounts.length > 0 ? p.accounts : []
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  // ------------------------------------------------------------ adding
  //
  // Adding a subscription happens right here: pick a provider, name it if
  // it's a second account, then sign in through the browser while the panel
  // follows omarchy-agent-account-add --events. The browser taking focus may
  // close the panel; the login carries on, and its result arrives as a
  // notification too.

  readonly property var addProviders: [
    { providerId: "claude", providerName: "Claude Code" },
    { providerId: "codex", providerName: "Codex" },
    { providerId: "grok", providerName: "Grok" }
  ]
  property string addStage: ""
  property string addProvider: ""
  property var addChecks: ({})
  property string addStatus: ""
  property string addCode: ""
  property string addUrl: ""
  property bool addNeedsPaste: false
  property string addResult: ""
  // Whether the sign-in in progress opened a private window, so reopening its
  // page does too.
  property bool addPrivate: false

  function addProviderName(id) {
    for (var i = 0; i < addProviders.length; i++)
      if (addProviders[i].providerId === id) return addProviders[i].providerName
    return id
  }

  function addAccount() {
    if (addStage === "running") return
    addStage = "pick"
    addChecks = ({})
    if (!checkProcess.running) checkProcess.running = true
  }

  function chooseAddProvider(id) {
    var state = addChecks[id] || ""
    if (state === "") return
    addProvider = id
    if (state === "additional") addStage = "name"
    else startAdd("")
  }

  function startAdd(label) {
    addPrivate = (addChecks[addProvider] || "") === "additional"
    addStatus = Commons.I18n.t("agents.starting")
    addCode = ""
    addUrl = ""
    // Claude's login offers pasting a code back whenever its page shows one,
    // and its prompt for it has no newline to read it by, so the field is
    // there from the start.
    addNeedsPaste = addProvider === "claude"
    addResult = ""
    addStage = "running"
    addProcess.command = ["omarchy-agent-account-add", "--events", addProvider].concat(label !== "" ? [label] : [])
    addProcess.running = true
  }

  function cancelAdd() {
    if (addProcess.running) addProcess.signal(15)
    addStage = ""
    root.focusKeys()
  }

  // A first sign-in keeps saying so until its limits arrive, rather than
  // flashing the choices again while the record is written.
  onBlankSlateChanged: if (!blankSlate && addStage === "done") addStage = ""

  function submitPaste(code) {
    if (!addProcess.running || code.trim() === "") return
    addProcess.write(code.trim() + "\n")
    addStatus = Commons.I18n.t("agents.checkingCode")
  }

  // The add command's own lines are tagged; everything else is the CLI
  // talking, and only two things in it matter here: a code to confirm in the
  // browser (Grok), and an invitation to paste one back (Claude).
  function handleAddLine(line) {
    var text = String(line).replace(/\u001b\[[0-9;]*m/g, "")
    var tagged = text.match(/^@@omarchy (status|done|error) (.*)$/)
    if (tagged) {
      if (tagged[1] === "status") {
        addStatus = tagged[2]
      } else {
        addResult = tagged[2]
        addStage = tagged[1]
        if (tagged[1] === "done") {
          usage.refreshLimits()
          addDoneTimer.restart()
          // Nothing to show yet means the sign-in is what counts as set up.
          if (usage.enabledProviders.length === 0 && !checkProcess.running) {
            addChecks = ({})
            checkProcess.running = true
          }
        }
      }
      return
    }
    var code = text.match(/^\s*([A-Z0-9]{4}-[A-Z0-9]{4})\s*$/)
    if (code) addCode = code[1]
    if (/paste code/i.test(text)) addNeedsPaste = true
    var url = text.match(/(https:\/\/\S+)/)
    if (url && addUrl === "") addUrl = url[1]
  }

  function reopenSignIn() {
    if (addUrl === "") return
    Util.execArgv(addPrivate ? ["omarchy-launch-browser", "--private", addUrl] : ["omarchy-launch-browser", addUrl])
  }

  // A few ways into making Omarchy your own, handed to the default agent.
  readonly property var starterPrompts: [
    { glyph: "󰏘", label: Commons.I18n.t("agents.theme"), prompt: "Make me a new Omarchy theme. Ask me what look or inspiration I have in mind, then build it following the Omarchy skill's theming guide and switch to it." },
    { glyph: "󰐱", label: Commons.I18n.t("agents.plugin"), prompt: "Make me a new Omarchy shell plugin. Ask me what I'd like it to do, then build it following the Omarchy skill's plugin guide and enable it." },
    { glyph: "󰣆", label: Commons.I18n.t("agents.app"), prompt: "Make me a new app for my Omarchy desktop. Ask me what it should do, then build it following the omarchy-app skill and install it so it shows up in the app launcher." }
  ]

  function startPrompt(prompt) {
    root.close()
    Util.execArgv(["omarchy-agent-prompt", prompt])
  }

  function renameAccount(p, account, label) {
    if (!p || !account) return
    Util.execArgv(["omarchy-agent-account-rename", p.providerId, String(account.id), label])
  }

  function useAccount(p, account) {
    if (!p || !account || account.active) return
    Util.execArgv(["omarchy-agent-account-use", p.providerId, String(account.id)])
  }

  function autoSwitchFor(p) {
    return !!p && !!p.accountSwitch && p.accountSwitch.mode === "auto"
  }

  function switchThreshold(p) {
    return p && p.accountSwitch ? Number(p.accountSwitch.threshold || 95) : 95
  }

  function setSwitchMode(p, mode) {
    if (!p || providerAccounts(p).length < 2 || mode === (autoSwitchFor(p) ? "auto" : "manual")) return
    Util.execArgv(["bash", "-c", 'omarchy-agent-account-mode "$1" "$2" >/dev/null && omarchy-agent-usage-update --limits-only "$1"',
                   "omarchy-agent-account-mode", p.providerId, mode])
  }

  // `m` flips autoswitch for the picked account's provider, or the first
  // provider with several accounts when nothing is picked.
  function toggleSwitchMode() {
    var p = pickedEntry ? pickedEntry.provider : (accountEntries.length > 0 ? accountEntries[0].provider : null)
    if (p) setSwitchMode(p, autoSwitchFor(p) ? "manual" : "auto")
  }

  function activateSelection() {
    var target = keyTarget
    if (!target) refreshNow()
    else if (target.kind === "add") addStage !== "" ? cancelAdd() : addAccount()
    else if (target.kind === "choice") chooseAddProvider(addProviders[target.index].providerId)
    else if (target.kind === "launch") launchAgent()
    else if (target.kind === "starter") startPrompt(starterPrompts[target.index].prompt)
    else if (target.kind === "providerSignin") signInAgain(providers[target.index], null)
    else if (target.kind === "signin") signInAgain(pickedEntry.provider, pickedEntry.account)
    else if (target.kind === "autoswitch") setSwitchMode(pickedEntry.provider, autoSwitchFor(pickedEntry.provider) ? "manual" : "auto")
    else if (pickedEntry && !pickedEntry.account.active) useAccount(pickedEntry.provider, pickedEntry.account)
  }

  function isPicked(p, account) {
    return !!pickedEntry && !!p && !!account
      && pickedEntry.provider.providerId === p.providerId && pickedEntry.account.id === account.id
  }

  // Hands the keyboard back to the panel after an inline edit.
  function focusKeys() {
    if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
  }

  function accountDetail(account) {
    var parts = []
    if (String(account.plan || "") !== "") parts.push(account.plan)
    if (account.resetCredits && Number(account.resetCredits.available) > 0)
      parts.push(freeResetsText(Number(account.resetCredits.available)))
    return parts.join(" · ")
  }

  // Only the agents `omarchy-agent-account-add` signs in get the link; any
  // other agent's sign-in trouble stays text, with its own help to follow.
  function supportsSignIn(p) {
    for (var i = 0; i < addProviders.length; i++)
      if (p && addProviders[i].providerId === p.providerId) return true
    return false
  }

  // A lapsed or missing sign-in is something you can fix from here; any other
  // trouble is only reported.
  function needsSignIn(item) {
    if (item && item.providerId && !supportsSignIn(item)) return false
    var status = String(item && item.usageStatusText || "")
    return status === "Sign-in expired" || status === "Waiting for auth"
  }

  // Whatever keeps the numbers from being current, said beside the last ones
  // known: they stay on show until a check succeeds again. A failed refresh
  // with numbers kept may leave the status empty and say why only in its help.
  function usageNote(item) {
    if (!item || needsSignIn(item)) return ""
    var status = String(item.usageStatusText || "")
    var stale = item.limitsStale === true || item.stale === true
    if (status === "" && !(stale && String(item.authHelpText || "") !== "")) return ""
    return helpDisplayText(item.authHelpText) || statusDisplayText(status)
  }

  // Sign an account that's already here in again, following along in the
  // add view just like adding one.
  function signInAgain(p, account) {
    if (!supportsSignIn(p) || addStage === "running") return
    addProvider = p.providerId
    addPrivate = !!account && account.primary !== true
    addStatus = Commons.I18n.t("agents.starting")
    addCode = ""
    addUrl = ""
    // Claude's login offers pasting a code back whenever its page shows one,
    // and its prompt for it has no newline to read it by, so the field is
    // there from the start.
    addNeedsPaste = addProvider === "claude"
    addResult = ""
    addStage = "running"
    addProcess.command = ["omarchy-agent-account-add", "--events", "--reauth",
      account && account.primary !== true ? String(account.id) : ":primary", p.providerId]
    addProcess.running = true
  }

  function resetCreditsText(credits) {
    if (!credits || !(Number(credits.available) > 0)) return ""
    var count = Number(credits.available)
    var expires = new Date(String(credits.nextExpiresAt || "")).getTime()
    if (isFinite(expires) && expires > nowMs) {
      return Commons.I18n.tn("agents.freeResetsExpires", count)
        .arg(Commons.I18n.formatNumber(count)).arg(formatDuration(expires - nowMs))
    }
    return freeResetsText(count)
  }

  function freeResetsText(count) {
    return Commons.I18n.tn("agents.freeResets", count).arg(Commons.I18n.formatNumber(count))
  }

  function planLabel(p) {
    var tier = String(p && p.tierLabel || "")
    if (tier === "Prepaid") return Commons.I18n.t("agents.tierPrepaid")
    return tier === "" ? "" : tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    var reset = new Date(String(resetAt || "")).getTime()
    var expired = isFinite(reset) && reset <= root.nowMs
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: expired ? 0 : Number(percent),
      resetAt: expired ? "" : String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // A model-scoped window ("Fable Weekly") is its own allowance, but it runs
  // on the same clock as the window it's named for, so it's shown attached to
  // that row rather than as a row of its own. One with nothing to attach to
  // still gets its own row.
  function scopedPart(title) {
    var match = String(title || "").match(/^(.+) (Session|Weekly|Monthly)$/)
    return match ? { model: match[1], window: match[2] } : null
  }

  function displayWindows(p) {
    var windows = limitWindows(p)
    var out = []
    var byTitle = {}
    for (var i = 0; i < windows.length; i++) {
      if (scopedPart(windows[i].title)) continue
      windows[i].scoped = []
      out.push(windows[i])
      byTitle[windows[i].title] = windows[i]
    }
    for (var j = 0; j < windows.length; j++) {
      var part = scopedPart(windows[j].title)
      if (!part) continue
      var base = byTitle[part.window]
      if (base) {
        base.scoped.push({ title: part.model, percent: windows[j].percent, resetAt: windows[j].resetAt })
      } else {
        windows[j].scoped = []
        out.push(windows[j])
      }
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return Commons.I18n.t("agents.durationNow")
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return Commons.I18n.t("agents.durationDaysHours").arg(Commons.I18n.formatNumber(days)).arg(Commons.I18n.formatNumber(hours % 24))
    if (hours > 0) return Commons.I18n.t("agents.durationHoursMinutes").arg(Commons.I18n.formatNumber(hours)).arg(Commons.I18n.formatNumber(minutes % 60))
    return Commons.I18n.t("agents.durationMinutes").arg(Commons.I18n.formatNumber(Math.max(1, minutes)))
  }

  // Window titles stay English in the records, where scopedPart() and the
  // collectors match on them; only what reaches the screen is translated.
  function windowDisplayTitle(title) {
    var value = String(title || "")
    if (value === "Session") return Commons.I18n.t("agents.windowSession")
    if (value === "Weekly") return Commons.I18n.t("agents.windowWeekly")
    if (value === "Monthly") return Commons.I18n.t("agents.windowMonthly")
    if (value === "Spend limit") return Commons.I18n.t("agents.windowSpendLimit")
    if (value === "Limit") return Commons.I18n.t("agents.windowLimit")
    var part = scopedPart(value)
    if (part && part.window === "Session") return Commons.I18n.t("agents.modelSession").arg(part.model)
    if (part && part.window === "Weekly") return Commons.I18n.t("agents.modelWeekly").arg(part.model)
    if (part && part.window === "Monthly") return Commons.I18n.t("agents.modelMonthly").arg(part.model)
    return value
  }

  function scopedAllowanceText(scoped, windowTitle) {
    var percent = Commons.I18n.formatNumber(Math.round(scoped.percent * 100))
    var value = String(windowTitle || "")
    if (value === "Session") return Commons.I18n.t("agents.scopedSession").arg(scoped.title).arg(percent)
    if (value === "Weekly") return Commons.I18n.t("agents.scopedWeekly").arg(scoped.title).arg(percent)
    if (value === "Monthly") return Commons.I18n.t("agents.scopedMonthly").arg(scoped.title).arg(percent)
    return Commons.I18n.t("agents.scopedOther").arg(scoped.title).arg(percent).arg(windowDisplayTitle(value))
  }

  // The collectors write a fixed English status; the ones that reach the
  // screen are shown in the current language.
  function statusDisplayText(status) {
    var value = String(status || "")
    if (value === "Balance unavailable") return Commons.I18n.t("agents.balanceUnavailable")
    if (value === "Out of credits") return Commons.I18n.t("agents.outOfCredits")
    var limits = value.match(/^(.+) limits unavailable$/)
    if (limits) return Commons.I18n.t("agents.providerLimitsUnavailable").arg(limits[1])
    var provider = value.match(/^(.+) unavailable$/)
    if (provider) return Commons.I18n.t("agents.providerUnavailable").arg(provider[1])
    if (value === "Sign-in expired") return Commons.I18n.t("agents.signInExpired")
    if (value === "Waiting for auth") return Commons.I18n.t("agents.waitingForAuth")
    if (value === "Limits paused") return Commons.I18n.t("agents.limitsPaused")
    return value
  }

  // The usage collectors cache their help lines in English, so the fixed
  // ones are translated here; commands stay verbatim as arguments, and raw
  // error text from a provider passes through as it came.
  function helpDisplayText(text) {
    var value = String(text || "")
    switch (value) {
    case "Run `claude auth login` to restore authoritative usage.":
      return Commons.I18n.t("agents.helpRunToRestoreUsage").arg("`claude auth login`")
    case "Run `codex login` to authenticate.":
      return Commons.I18n.t("agents.helpRunToAuthenticate").arg("`codex login`")
    case "Start Grok, or run `grok login`, to sign in.":
      return Commons.I18n.t("agents.helpStartOrRunToSignIn").arg("Grok").arg("`grok login`")
    case "Start Grok to see its limits; signing in again is not needed.":
      return Commons.I18n.t("agents.helpStartToSeeLimits").arg("Grok")
    case "Grok's saved sign-in expired. Start Grok to refresh it.":
      return Commons.I18n.t("agents.helpSignInExpired").arg("Grok")
    case "Set FIREWORKS_API_KEY, run `firectl set-api-key`, or sign in to Fireworks in pi or opencode.":
      return Commons.I18n.t("agents.helpFireworksSignIn").arg("FIREWORKS_API_KEY").arg("`firectl set-api-key`")
    case "codex not found in PATH":
      return Commons.I18n.t("agents.helpNotInPath").arg("codex")
    case "Fireworks usage scan failed":
      return Commons.I18n.t("agents.helpScanFailed").arg("Fireworks")
    }
    return value
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  function balanceAlarming(b) {
    return !!b && b.funded > 0 && b.remaining / b.funded <= 0.1
  }

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + Commons.I18n.formatNumber(amount, 2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var spent = formatMoney(b.spent, b.currency)
    var funded = formatMoney(b.funded, b.currency)
    return b.estimated
      ? Commons.I18n.t("agents.balanceSpentEstimated").arg(spent).arg(funded)
      : Commons.I18n.t("agents.balanceSpent").arg(spent).arg(funded)
  }

  // ---------------------------------------------------------------- summary
  //
  // The hero's line rotates through what the token counts add up to across
  // every agent, now that they no longer get charts of their own.

  readonly property var summaryPhrases: {
    var rev = usage.dataRevision
    var week = 0
    var today = 0
    var prompts = 0
    var sessions = 0
    var byDay = {}
    var byModel = {}
    var providers = usage.enabledProviders
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      var days = p.recentDays || []
      for (var d = 0; d < days.length; d++) {
        var tokens = Number(days[d].messageCount || 0)
        week += tokens
        byDay[days[d].date] = (byDay[days[d].date] || 0) + tokens
      }
      today += Number(p.todayTotalTokens || 0)
      if (p.hasPromptStats !== false) {
        prompts += Number(p.todayPrompts || 0)
        sessions += Number(p.todaySessions || 0)
      }
      var models = p.modelUsage || {}
      for (var id in models) {
        var bucket = models[id] || {}
        var total = Number(bucket.inputTokens || 0) + Number(bucket.outputTokens || 0)
          + Number(bucket.cacheReadInputTokens || 0) + Number(bucket.cacheCreationInputTokens || 0)
        var name = usage.friendlyModelName(id)
        byModel[name] = (byModel[name] || 0) + total
      }
    }

    var phrases = []
    if (week > 0) phrases.push(Commons.I18n.tn("agents.tokensThisWeek", week).arg(usage.formatTokenCount(week)))
    if (today > 0) phrases.push(Commons.I18n.tn("agents.tokensToday", today).arg(usage.formatTokenCount(today)))
    var topModel = ""
    for (var model in byModel) if (topModel === "" || byModel[model] > byModel[topModel]) topModel = model
    if (topModel !== "" && byModel[topModel] > 0) phrases.push(Commons.I18n.t("agents.mostlyModel").arg(topModel))
    var busiest = ""
    for (var date in byDay) if (busiest === "" || byDay[date] > byDay[busiest]) busiest = date
    if (busiest !== "" && byDay[busiest] > 0) phrases.push(Commons.I18n.t("agents.busiestDay").arg(dayName(busiest)))
    if (prompts > 0) phrases.push(Commons.I18n.tn("agents.promptsToday", prompts).arg(Commons.I18n.formatNumber(prompts)))
    if (sessions > 0) phrases.push(Commons.I18n.tn("agents.sessionsToday", sessions).arg(Commons.I18n.formatNumber(sessions)))
    return phrases
  }
  property int phraseIndex: 0
  // Every record that lands rebuilds the phrases, and opening the panel
  // refreshes each agent in turn. Indexing the live list would swap the line
  // on each of those, so the hero holds what it shows until the next fade.
  property string shownPhrase: ""
  readonly property string heroPhrase: addStage !== "" || blankSlate
    ? addHeading
    : (shownPhrase !== "" ? shownPhrase : Commons.I18n.t("agents.subscriptions"))

  function showPhrase() {
    var n = summaryPhrases.length
    shownPhrase = n > 0 ? summaryPhrases[phraseIndex % n] : ""
  }

  onSummaryPhrasesChanged: if (shownPhrase === "" || summaryPhrases.length <= 1) showPhrase()

  // The held line was written in the language it was shown in; once a new
  // language's strings arrive and the phrases rebuild, show it again.
  Connections {
    target: Commons.I18n
    function onStringsChanged() { Qt.callLater(root.showPhrase) }
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return Qt.locale(Commons.I18n.formatLocale).dayName([7, 1, 2, 3, 4, 5, 6][parsed.getDay()])
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    var providers = usage.enabledProviders
    for (var i = 0; i < providers.length; i++) {
      var count = Number(providers[i].syncDeviceCount || 0)
      if (providers[i].syncEnabled && count > 0)
        return Commons.I18n.tn("agents.merged", count).arg(Commons.I18n.formatNumber(count))
    }
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Commons.Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Always in the bar: on a machine with no agent yet, the panel is where you
  // set one up.
  readonly property bool anySignedIn: {
    for (var id in addChecks)
      if (addChecks[id] !== "first") return true
    return false
  }
  // Local history counts as set up, so a machine with no subscription still
  // gets its summary rather than the picker.
  readonly property bool blankSlate: usage.enabledProviders.length === 0 && !anySignedIn
  // Choosing a provider: asked for with the +, or simply what the panel is
  // while nothing is set up. It's derived rather than switched into, so
  // records that load a moment after the panel opens take its place.
  readonly property bool picking: addStage === "pick" || (blankSlate && addStage === "")
  // The + in the hero turns into the X that leaves adding. A first setup has
  // nothing to go back to until an agent is chosen.
  readonly property bool addButtonShown: !blankSlate || !picking

  // Adding takes over the hero's line, and the cursor starts over.
  readonly property string addHeading: picking || addProvider === ""
    ? Commons.I18n.t("agents.addAccount")
    : Commons.I18n.t("agents.addProviderAccount").arg(addProviderName(addProvider))
  onAddStageChanged: {
    phraseSwap.stop()
    if (hero) hero.metaOpacity = 1.0
    resetKeys()
  }

  // A first setup ends when the records land, which swaps the rows under the
  // cursor without any stage change.
  onPickingChanged: resetKeys()

  // Picking an agent to add starts on the first one, ready for Enter. The
  // rows follow the same stage change, so the cursor waits a tick for them.
  function resetKeys() {
    cursorActive = false
    keyRow = 0
    keyColumn = 0
    Qt.callLater(function() { if (picking) pointAt("choice", 0) })
  }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    if (addStage !== "running") addStage = ""
    resetKeys()
    if (usage.enabledProviders.length === 0 && !checkProcess.running) checkProcess.running = true
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  Process {
    id: checkProcess
    running: false
    command: ["omarchy-agent-account-add", "--check"]
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).trim().split(" ")
        if (parts.length !== 2) return
        var checks = Object.assign({}, root.addChecks)
        checks[parts[0]] = parts[1]
        root.addChecks = checks
      }
    }
  }

  Process {
    id: addProcess
    running: false
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleAddLine(line) } }
    onExited: {
      if (root.addStage === "running") {
        root.addResult = Commons.I18n.t("agents.signInUnfinished")
        root.addStage = "error"
      }
    }
  }

  Timer {
    id: addDoneTimer
    interval: 2500
    onTriggered: if (root.addStage === "done" && !root.blankSlate) root.addStage = ""
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    interval: 2800
    // Vista: only with a hero to fade; the Vista sheet lists every phrase at
    // once (its Summary tab), so nothing rotates or animates while it is open.
    running: !!root.hero && root.opened && root.summaryPhrases.length > 1 && root.addStage === "" && !root.blankSlate
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: Style.duration(150); easing.type: Easing.OutCubic
    }
    ScriptAction {
      script: {
        root.phraseIndex = (root.phraseIndex + 1) % Math.max(1, root.summaryPhrases.length)
        root.showPhrase()
      }
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: Style.duration(200); easing.type: Easing.OutCubic
    }
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else root.toggle()
    }
  }


  // =========================================================================
  // Vista UI (ocko.vista-agents). Everything above is stock 4.5.0 apart from
  // the one "Vista:" edit (the hero phrase timer); everything below replaces
  // stock's card and its components (AddView, ProviderSection, ...).
  //
  // No Vista original: stock's dashboard as a Vista property sheet, one tab per
  // subscription plus a Summary tab, with Vista group boxes, progress bars
  // and a report-view list (VistaAgents.qml). Proportions are powercfg.cpl's
  // 252-DLU property page; Add, Launch Agent and Refresh sit at the page's
  // bottom right as Task Manager's End Task / New Task do.
  // =========================================================================

  // ---- Vista: 4.0.6 single-provider helpers ----
  // 4.5 shows every subscription on one page; the sheet shows one per tab,
  // so the selected-provider state and the per-provider tables 4.5 dropped
  // (tokens by day, tokens by model) come back here, reading the 4.5 records.

  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null
  // 4.5's windows, scoped (per-model) allowances attached to their window.
  readonly property var limits: displayWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var balance: provider ? (provider.balance || null) : null

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  // 4.5's Ctrl+Up/Down reorder, for the selected tab: the tab moves left or
  // right and stays selected (the selection follows the provider id).
  function vistaMoveProvider(dy) {
    if (!provider) return
    var to = clamp(providerIndex + dy, 0, providers.length - 1)
    if (to === providerIndex) return
    selectedProviderId = provider.providerId
    usage.moveProvider(provider.providerId, to)
  }

  // The plan you pay for, or what keeps its numbers from being current.
  function heroMeta(p) {
    if (!p) return ""
    var status = String(p.usageStatusText || "")
    if (status !== "") return statusDisplayText(status)
    var plan = planLabel(p)
    return plan === "" ? "Subscription" : plan
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  // 4.5's dayName() is the full localized name; the day rows want it short.
  function shortDayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return Qt.locale(Commons.I18n.formatLocale).dayName([7, 1, 2, 3, 4, 5, 6][parsed.getDay()], Locale.ShortFormat)
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return shortDayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : shortDayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // ---- Vista: the card ----

  // The sheet draws its own window: no rounded popup card behind it. The
  // content sits in KeyboardPanel's Loader, so walk up to the card.
  function vistaBareCard(item) {
    var card = item ? item.parent : null
    while (card && !("radius" in card && "borderSpec" in card)) card = card.parent
    if (card) {
      card.color = "transparent"
      card.radius = 0
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    padding: 0
    borderSpec: Border.none()
    contentWidth: panel.fittedContentWidth(panel.loadedContent ? panel.loadedContent.implicitWidth : Style.space(400))
    contentHeight: Math.max(1, panel.loadedContentHeight)

    // Lazy, like stock: built on first open. The root reads panelFlick, hero,
    // column and providerSections off it; only panelFlick (the sheet, for
    // contentY) means anything here.
    content: PanelKeyCatcher {
      id: keyCatcher
      property Item panelFlick: sheet
      property Item hero: null
      property Item column: null
      property Item providerSections: null
      implicitWidth: sheet.width
      implicitHeight: sheet.height
      anchors.fill: parent
      // An inline edit (an account name, the add flow's fields) gets the keys.
      blocked: sheet.editing
      reorderable: root.addStage === "" && !root.renaming
      onReorderRequested: function(dy) { root.vistaMoveProvider(dy) }
      Component.onCompleted: root.vistaBareCard(keyCatcher)

      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && root.addStage === "" && !root.blankSlate) sheet.step(dx)
        if (dy !== 0) sheet.scrollBy(dy * Style.space(56))
      }
      onActivateRequested: if (root.addStage === "") root.refreshNow()
      onCloseRequested: {
        if (root.addStage !== "") root.cancelAdd()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "m" || t === "M") root.toggleSwitchMode()
      }

      VistaAgents {
        id: sheet
        host: root
        usage: usage
        maxHeight: panel.availableCardHeight
      }
    }
  }
}
