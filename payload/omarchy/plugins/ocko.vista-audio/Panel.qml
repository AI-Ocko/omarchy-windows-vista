// ocko.vista-audio: omarchy.audio for the Vista notification area (Windows Vista theme
// only; see omarchy/vista/bin/vista-mode). Lines 9-671 are the logic of
// /usr/share/omarchy/shell/plugins/panels/audio/Panel.qml (Omarchy 4.0.6,
// sha256 a683e771f495837170371da658e00cef1dacc89d0220d44d9e0e988ab2bbd2c0,
// lines 1-650), with each change marked "Vista:". The card below that is rebuilt
// as sndvol32's flyout, context menu, mixer and Properties. Re-diff the logic
// against a newer Omarchy: diff <(sed -n 9,671p Panel.qml) <(sed -n 1,650p <stock>)

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model
import "../../vista/qml"

Panel {
  id: root
  moduleName: "omarchy.audio"
  ipcTarget: "omarchy.audio"

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activeMediaPlayer: mediaService ? mediaService.activePlayer : null

  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isSink && !n.isStream && isAudioSource(n)) {
        var name = n.name || ""
        if (name === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !isPlaybackStream(n)) continue
      // A tuning's output is a playback stream too, but it is the processing
      // itself rather than an application, so it does not belong in the list.
      if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue
      list.push(n)
    }
    return list
  }

  property var sinkAvailability: ({})
  property bool sinkAvailabilityLoaded: false

  // Identify true playback streams without reading node.properties here:
  // PwNode.properties is invalid until the node is bound, and reading it while
  // capture streams are appearing (for example, when Voxtype starts recording)
  // can destabilize Quickshell's Pipewire service. Quickshell versions differ
  // in how `type` is exposed (media.class, enum name, or numeric enum), but
  // playback streams consistently accept audio input from clients and publish
  // `isSink: true`; capture streams publish as stream sources.
  function isPlaybackStream(node) {
    return Model.isPlaybackStream(node)
  }

  function isAudioSource(node) {
    return Model.isAudioSource(node)
  }

  property var cachedAudioSinks: []
  property var cachedAudioSources: []

  readonly property var rawAudioSinks: {
    var list = []
    for (var i = 0; i < candidateSinks.length; i++)
      if (sinkAvailable(candidateSinks[i])) list.push(candidateSinks[i])
    if (sink && list.indexOf(sink) < 0) list.unshift(sink)
    return list
  }

  readonly property var rawAudioSources: {
    var list = candidateSources.slice()
    if (source && list.indexOf(source) < 0) list.unshift(source)
    return list
  }

  readonly property var audioSinks: rawAudioSinks.length > 0 ? rawAudioSinks : cachedAudioSinks
  readonly property var audioSources: rawAudioSources.length > 0 ? rawAudioSources : cachedAudioSources

  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < candidateStreams.length; i++)
      if (candidateStreams[i].audio) list.push(candidateStreams[i])
    return list
  }

  // Feed Repeaters with panel-local snapshots instead of the live PipeWire
  // model. PipeWire can remove nodes while Quickshell is dispatching the
  // removal signal; rebuilding a Repeater from that signal path has crashed
  // in Quickshell's PipeWire service. The snapshot timer lets that mutation
  // settle first, and closed panels keep their repeaters detached entirely.
  property var displayAudioSinks: []
  property var displayAudioSources: []
  property var displayAudioStreams: []

  // A DSP sink -- a speaker tuning, or EasyEffects -- can be the selected output
  // without being where loudness lives: changing its volume alters the level going
  // *into* the processing, so the slider would move while the speakers did not,
  // and on a chain with a limiter it would change the tone as well.
  //
  // omarchy-audio-output-sink resolves the *current* default output through any
  // such sink to the physical one, which is the same definition the volume keys
  // and the output switcher use. Resolving the default (rather than "whatever a
  // tuning fronts") is what keeps this correct when headphones or HDMI are
  // selected while a tuning still exists.
  property string volumeSinkName: ""

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink) return sink
    if (volumeSinkName === String(sink.name)) return sink
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio)
        return n
    }
    return sink
  }

  // Re-resolve whenever the selected output changes; the timer below is only a
  // safety net for the tuning being applied or removed underneath us.
  onSinkChanged: resolveVolumeSink()

  function resolveVolumeSink() {
    if (!volumeSinkProc.running) volumeSinkProc.running = true
  }

  // Vista: the louder channel, so Balance survives a Volume move (level()).
  readonly property real outputVolume: volumeSink && volumeSink.audio ? root.level(volumeSink.audio) : 0
  readonly property bool outputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  onRawAudioSinksChanged: if (rawAudioSinks.length > 0) cachedAudioSinks = rawAudioSinks
  onRawAudioSourcesChanged: if (rawAudioSources.length > 0) cachedAudioSources = rawAudioSources

  // Single cursor model shared by keyboard and mouse. Sections:
  //   "output"  — output slider + sink device list
  //   "input"   — input slider + source device list
  //   "streams" — per-app playback streams
  // selectedIndex semantics within a section:
  //   -1            → on the slider row (h/l adjusts volume, m/Enter mute)
  //   0..N-1        → on the Nth device/stream row
  // Visuals derive from hasCursor/current via CursorSurface, never
  // from containsMouse — that's what keeps the highlight unique across
  // keyboard + mouse like wifi does.
  property string focusSection: "output"
  property int selectedIndex: -1
  property bool cursorActive: false

  // "header" is a virtual section for the hero output mute toggle; it sits
  // above the output section so the speaker can be muted from the keyboard.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  // Only channels that actually exist get a vote. A box with no default source
  // would otherwise report "input unmuted" forever, leaving the hero switch
  // able to mute but never to unmute.
  readonly property bool hasOutput: !!(volumeSink && volumeSink.audio)
  readonly property bool hasInput: !!(source && source.audio)
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)
  readonly property string toggleHint: anyAudible ? "Mute" : "Unmute"

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Commons.Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Commons.Color.accent)
    : "transparent"

  function sectionCount(section) {
    if (section === "output") return displayAudioSinks.length
    if (section === "input") return displayAudioSources.length
    if (section === "streams") return displayAudioStreams.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "output") return true
    if (section === "input") return displayAudioSources.length > 0 || !!source
    if (section === "streams") return displayAudioStreams.length > 0
    return false
  }

  function sectionHasSlider(section) {
    if (section === "output") return true
    if (section === "input") return !!source
    return false  // stream rows carry their own sliders inline; not a section-level slider
  }

  // Order of visible sections, recomputed reactively so dropping a section
  // (e.g. no input devices) doesn't leave the cursor pointing at it.
  readonly property var visibleSections: {
    var list = []
    if (sectionVisible("output")) list.push("output")
    if (sectionVisible("input")) list.push("input")
    if (sectionVisible("streams")) list.push("streams")
    return list
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (sections.length === 0) return
    if (focusSection === "header") {
      if (delta > 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(sections[0]) ? -1 : 0 }
      return
    }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(focusSection) ? -1 : 0; return }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1  // last device index
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0  // -1 = slider row

    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; return }
      // Fall through to next section.
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      }
    } else {
      if (idx > floor) { selectedIndex = idx - 1; return }
      // Escape upward.
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        var prevMax = sectionCount(focusSection) - 1
        selectedIndex = prevMax >= 0 ? prevMax : (sectionHasSlider(focusSection) ? -1 : 0)
      } else {
        focusSection = "header"
      }
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    selectedIndex = -1
  }

  function moveSection(delta) {
    var sections = visibleSections
    if (sections.length === 0) return
    var current = sections.indexOf(focusSection)
    if (current < 0) current = delta > 0 ? -1 : 0
    var next = (current + delta + sections.length) % sections.length
    focusSection = sections[next]
    selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
    cursorActive = true
  }

  // Adjust the slider associated with the focused section. Output and
  // input sliders are real volume controls; on stream rows h/l adjusts
  // that stream's volume (so keyboard parity with the inline slider).
  // For device rows (selectedIndex >= 0 in output/input) h/l is a no-op
  // — the cursor is on a discrete row, not on the slider, and silently
  // moving the global slider would surprise the user.
  function adjustVolume(delta) {
    if (focusSection === "output" && selectedIndex === -1) {
      setOutputVolume(outputVolume + delta)
      return
    }
    if (focusSection === "input" && selectedIndex === -1) {
      setInputVolume(inputVolume + delta)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0 && selectedIndex < displayAudioStreams.length) {
      var s = displayAudioStreams[selectedIndex]
      if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1.5, s.audio.volume + delta))
    }
  }

  // Enter/Space: activate whatever the cursor is on.
  function activateCursor() {
    if (focusSection === "header") { toggleAllMuted(); return }
    if (focusSection === "output") {
      if (selectedIndex === -1) { toggleOutputMute(); return }
      var sink = displayAudioSinks[selectedIndex]
      if (sink) setDefaultSink(sink)
      return
    }
    if (focusSection === "input") {
      if (selectedIndex === -1) { toggleInputMute(); return }
      var src = displayAudioSources[selectedIndex]
      if (src) setDefaultSource(src)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0) {
      var st = displayAudioStreams[selectedIndex]
      if (st && st.audio) st.audio.muted = !st.audio.muted
    }
  }

  onOpenedChanged: {
    if (opened) {
      refreshDisplayAudioModels()
      focusSection = "output"
      selectedIndex = -1  // first keyboard cursor reveal starts on the output slider
      cursorActive = false
      // Vista: no scroll area to reset (was Qt.callLater(resetScroll))
    } else if (!mixerOpen) {  // Vista: the mixer, not the flyout, lists nodes
      clearDisplayAudioModels()
    }
  }

  // Clamp / repair the cursor whenever any list refreshes underneath us.
  onAudioSinksChanged: scheduleDisplayAudioModelRefresh()
  onAudioSourcesChanged: scheduleDisplayAudioModelRefresh()
  onAudioStreamsChanged: scheduleDisplayAudioModelRefresh()

  function listSnapshot(list) {
    return Model.listSnapshot(list)
  }

  function refreshDisplayAudioModels() {
    if (!mixerOpen) return  // Vista
    displayAudioSinks = listSnapshot(audioSinks)
    displayAudioSources = listSnapshot(audioSources)
    displayAudioStreams = listSnapshot(audioStreams)
    clampCursor()
  }

  function scheduleDisplayAudioModelRefresh() {
    if (!mixerOpen) return  // Vista
    audioModelRefreshTimer.restart()
  }

  function clearDisplayAudioModels() {
    audioModelRefreshTimer.stop()
    displayAudioSinks = []
    displayAudioSources = []
    displayAudioStreams = []
  }

  // Keep the keyboard-focused row inside the visible viewport of the
  // ScrollView. Each cursor target (slider rows, SinkRow, SourceRow,
  // StreamRow) calls this when it gains hasCursor. Without it, j/k can
  // walk the selection off-screen — wifi uses ListView.positionViewAtIndex
  // for this; we don't have that affordance with a multi-section Column.
  function resetScroll() {
    if (!scrollArea) return
    var flick = scrollArea.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = 6
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maxY <= Style.space(24) || (root.focusSection === "output" && root.selectedIndex === -1)) {
      flick.contentY = 0
      return
    }
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maxY, bottom + margin - flick.height))
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    // "header" is virtual and never appears in visibleSections, so it has to
    // be let through: muting republishes the PipeWire snapshot, and clamping
    // would knock the cursor off the hero switch on every toggle.
    if (focusSection === "header") return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = visibleSections[0]
      selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      return
    }
    var count = sectionCount(focusSection)
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0
    if (selectedIndex > count - 1) selectedIndex = Math.max(floor, count - 1)
    if (selectedIndex < floor) selectedIndex = floor
  }

  function outputIcon(volume) {
    // Match the old Waybar pulseaudio glyph set. The Material Design speaker
    // icons render visually smaller in JetBrainsMono Nerd Font.
    if (!sink || !sink.audio) return ""
    if (isHeadphones(sink)) return "󰋋"
    if (outputMuted) return ""
    var v = volume === undefined ? outputVolume : volume
    if (v >= 0.67) return ""
    if (v >= 0.34) return ""
    if (v > 0) return ""
    return ""
  }

  function inputIcon() {
    if (!source || !source.audio) return "󰍭"
    return inputMuted ? "󰍭" : "󰍬"
  }

  // Playful mood-name for a given output volume. Mirrors the brightness
  // panel's brightnessName ladder; bands are wide enough that small
  // tweaks don't rename the room you're in.
  function outputVolumeName(volume, muted) {
    return Model.outputVolumeName(volume, muted)
  }

  function setOutputVolume(v) {
    if (!volumeSink || !volumeSink.audio) return outputVolume
    var volume = Math.max(0, Math.min(1, v))
    root.setLevel(volumeSink, volume, 1)  // Vista: keeps Balance
    return volume
  }

  function showVolumeOsd(volume) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: outputIcon(volume),
      value: Math.round(volume * 100)
    }))
  }

  function setInputVolume(v) {
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (volumeSink && volumeSink.audio) volumeSink.audio.muted = !volumeSink.audio.muted
  }

  function toggleInputMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  // The hero switch is the whole panel's on/off, so it carries both channels
  // at once. It reads as on while anything is still audible, which keeps
  // muting a single channel from the row below flipping the master switch.
  function toggleAllMuted() {
    var mute = anyAudible
    if (hasOutput) volumeSink.audio.muted = mute
    if (hasInput) source.audio.muted = mute
  }

  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached([
        "omarchy-audio-output-set-default",
        String(node.id),
        String(node.name)
      ])
    }
  }

  function setDefaultSource(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached([
        "omarchy-audio-input-set-default",
        String(node.id),
        String(node.name)
      ])
    }
  }

  function sinkAvailable(node) {
    if (!node || !node.name || !sinkAvailabilityLoaded) return true
    var name = String(node.name)
    return sinkAvailability[name] !== false
  }

  function updateSinkAvailability(raw) {
    sinkAvailability = Model.parseSinkAvailability(raw)
    sinkAvailabilityLoaded = true
  }

  function friendlyDeviceLabel(text) {
    return Model.friendlyDeviceLabel(text)
  }

  function nodeLabel(node) {
    return Model.nodeLabel(node)
  }

  function nodeProps(node) {
    return Model.nodeProps(node)
  }

  function isHeadphones(node) {
    return Model.isHeadphones(node)
  }

  function sinkGlyph(node) {
    return Model.sinkGlyph(node)
  }

  function sourceGlyph(node) {
    return Model.sourceGlyph(node)
  }

  function friendlyStreamLabel(label) {
    return Model.friendlyStreamLabel(label)
  }

  function streamLabelKey(label) {
    return Model.streamLabelKey(label)
  }

  function streamLabelIsGeneric(label) {
    return Model.streamLabelIsGeneric(label)
  }

  function rawStreamLabel(node) {
    return Model.rawStreamLabel(node)
  }

  function mprisPlayerLabel(player) {
    return Model.mprisPlayerLabel(player)
  }

  function mprisPlayerIsProxy(player) {
    return Model.mprisPlayerIsProxy(player)
  }

  function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
    return Model.streamRepresentsMprisPlayer(streamLabel, playerLabel)
  }

  function mprisLabelsFor(predicate) {
    return Model.mprisLabelsFor(mprisPlayers, predicate)
  }

  function matchingMprisStreamLabel(label) {
    return Model.matchingMprisStreamLabel(label, mprisPlayers)
  }

  function unmatchedMprisStreamLabel(label) {
    // Spotify exposes its PipeWire stream as "audio-src". For generic stream
    // names, use the one MPRIS player not already represented by another audio
    // stream (e.g. Chromium, or ALSA apps like cliamp).
    return Model.unmatchedMprisStreamLabel(label, mprisPlayers, displayAudioStreams)
  }

  function streamLabel(node) {
    return Model.streamLabel(node, mprisPlayers, displayAudioStreams)
  }

  function streamRepresentsPlayer(node, player) {
    return Model.streamRepresentsPlayer(node, player, mprisPlayers, displayAudioStreams)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  PwObjectTracker { objects: root.candidateSinks }
  PwObjectTracker { objects: root.candidateSources }
  PwObjectTracker { objects: root.audioStreams }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: root.source
    enabled: root.mixerOpen && !!root.source  // Vista: the meter is in the mixer
  }

  Process {
    id: sinkAvailabilityProc
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateSinkAvailability(text)
    }
  }

  Process {
    id: volumeSinkProc
    command: ["omarchy-audio-output-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.volumeSinkName = String(text).trim()
    }
  }

  Timer {
    interval: 5000
    running: root.mixerOpen  // Vista: only the mixer lists sinks
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
  }

  // Runs whether or not the panel is open: the bar shows and scrolls the output
  // volume too, so an unresolved sink there would read and change the virtual
  // tuning sink instead of the speakers.
  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.resolveVolumeSink()
  }

  Timer {
    id: audioModelRefreshTimer
    interval: 75
    repeat: false
    onTriggered: root.refreshDisplayAudioModels()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.outputIcon()
    // Vista: right-click is sndvol's context menu (mute-all moved to the mixer's
    // master column); a double-click opens the mixer, a click the flyout.
    onPressed: function(b) {
      if (b === Qt.RightButton) { root.menuOpen = !root.menuOpen; return }
      if (b === Qt.LeftButton) {
        var now = Date.now()
        if (now - root.lastLeftPress < Qt.styleHints.mouseDoubleClickInterval) {
          root.lastLeftPress = 0
          root.openMixer(false)
          return
        }
        root.lastLeftPress = now
      }
      root.toggle()
    }

    onWheelMoved: function(delta) {
      if (!root.hasOutput) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var volume = root.setOutputVolume(root.outputVolume + wheel.steps * 0.05)
      root.showVolumeOsd(volume)
    }
  }


  // =========================================================================
  // Vista UI (ocko.vista-audio). Everything above is stock (see the header) apart
  // from the lines marked "Vista:". Everything below replaces stock's card.
  //
  // Geometry is sndvol32.exe's own dialog templates (Vista SP2), converted from
  // dialog units at Tahoma 8 / 96 dpi (1 DLU = 1.5 px across, 13/8 px down):
  //   106  the tray "Volume" flyout, 50 x 80
  //   101  the mixer's master column, 90 x 150; 102 a line column, 70 x 150
  //   107  Properties, 224 x 250
  // Strings and menus are the exe's STRING and MENU 150 resources.
  // =========================================================================

  property bool mixerOpen: false
  property bool menuOpen: false
  property bool propsOpen: false
  // Keyboard focus in the mixer: an index into shownColumns.
  property int mixerFocus: 0
  // Columns hidden through Properties > "Show the following volume
  // controls", by column key. Kept in this widget's shell.json entry
  // (settings.hiddenColumns, under the stock id), which stock ignores.
  readonly property var hiddenColumns: {
    var h = {}
    var keys = settings && settings.hiddenColumns instanceof Array ? settings.hiddenColumns : []
    for (var i = 0; i < keys.length; i++) h[keys[i]] = true
    return h
  }
  property real lastLeftPress: 0
  // The flyout's value tip also shows for a moment after a key press.
  property bool tipFlash: false

  property string propsMode: "playback"
  property int propsDevice: -1
  property var propsHidden: ({})

  function s(n) { return Style.space(n) }
  function du(x) { return Style.space(Math.round(x * 1.5)) }
  function dv(y) { return Style.space(Math.round(y * 13 / 8)) }

  // Vista draws the flyout, the menu and the windows itself, so the shell's
  // card underneath must not show at their corners or shadow.
  function vistaBareCard(item) {
    var card = item && item.parent ? item.parent.parent : null
    if (card && "radius" in card) {
      card.color = "transparent"
      card.radius = 0
    }
  }

  // ---- levels and balance -------------------------------------------------
  // Vista's volume is the louder channel and Balance the ratio between the two,
  // so moving Volume keeps Balance. PwNodeAudio.volume is the channel
  // average, so channels are written through `volumes` directly.
  function level(a) {
    if (!a) return 0
    var v = a.volumes
    if (!v || v.length === 0) return a.volume
    var m = 0
    for (var i = 0; i < v.length; i++) m = Math.max(m, v[i])
    return m
  }

  function setLevel(node, v, max) {
    if (!node || !node.audio) return 0
    var a = node.audio
    var lvl = Math.max(0, Math.min(max, v))
    var old = a.volumes
    var top = level(a)
    if (!old || old.length < 2 || top <= 0) {
      a.volume = lvl
      return lvl
    }
    var out = []
    for (var i = 0; i < old.length; i++) out.push(old[i] * lvl / top)
    a.volumes = out
    return lvl
  }

  // [left, right] channel indices, or null when the node is not plain
  // stereo; Balance is then shown disabled.
  function stereoPair(a) {
    if (!a || !a.channels || a.channels.length !== 2) return null
    var l = -1, r = -1
    for (var i = 0; i < 2; i++) {
      if (a.channels[i] === PwAudioChannel.FrontLeft) l = i
      else if (a.channels[i] === PwAudioChannel.FrontRight) r = i
    }
    return l >= 0 && r >= 0 ? [l, r] : null
  }

  // -1 is hard left, 1 hard right.
  function balanceOf(a) {
    var c = stereoPair(a)
    if (!c) return 0
    var lv = a.volumes[c[0]], rv = a.volumes[c[1]]
    var m = Math.max(lv, rv)
    return m > 0 ? (rv - lv) / m : 0
  }

  function setBalance(a, b) {
    var c = stereoPair(a)
    if (!c) return
    var m = level(a)
    var out = []
    for (var i = 0; i < a.volumes.length; i++) out.push(a.volumes[i])
    out[c[0]] = m * (b > 0 ? 1 - b : 1)
    out[c[1]] = m * (b < 0 ? 1 + b : 1)
    a.volumes = out
  }

  function nudgeOutput(delta) {
    setOutputVolume(outputVolume + delta)
    tipFlash = true
    tipTimer.restart()
  }

  Timer {
    id: tipTimer
    interval: 1500
    onTriggered: root.tipFlash = false
  }

  // ---- mixer columns ------------------------------------------------------
  // master (the resolved volume sink), every other output, the default
  // input, then each app stream. Built from the panel-local snapshots, like
  // stock's lists, so a vanishing node never rebuilds a Repeater mid-signal.
  readonly property var mixerColumns: {
    var cols = [{ kind: "master", node: volumeSink, key: "master" }]
    for (var i = 0; i < displayAudioSinks.length; i++) {
      var n = displayAudioSinks[i]
      if (n && n !== volumeSink) cols.push({ kind: "output", node: n, key: "out:" + n.name })
    }
    if (source) cols.push({ kind: "input", node: source, key: "in" })
    for (var j = 0; j < displayAudioStreams.length; j++) {
      var st = displayAudioStreams[j]
      // By label, not node id: an app's stream gets a new id every run.
      if (st) cols.push({ kind: "stream", node: st, key: "app:" + streamLabel(st) })
    }
    return cols
  }

  readonly property var shownColumns: {
    var out = []
    for (var i = 0; i < mixerColumns.length; i++)
      if (mixerColumns[i].kind === "master" || !hiddenColumns[mixerColumns[i].key]) out.push(mixerColumns[i])
    return out
  }

  onShownColumnsChanged: if (mixerFocus > shownColumns.length - 1) mixerFocus = Math.max(0, shownColumns.length - 1)

  // Stock labels a device by node.nick, which every port of one card can
  // share (the EVO4's inputs all say "EVO4"). Vista named the line, so where a
  // nick is not unique among `among`, use the node's description instead.
  function vistaLabel(n, among) {
    var nick = nodeLabel(n)
    for (var i = 0; i < among.length; i++)
      if (among[i] && among[i] !== n && nodeLabel(among[i]) === nick) return friendlyDeviceLabel(n.description || nick)
    return nick
  }

  function columnCaption(col) {
    if (!col || !col.node) return ""
    if (col.kind === "master") return "Volume Control"
    if (col.kind === "stream") return streamLabel(col.node)
    return vistaLabel(col.node, displayAudioSinks.concat(displayAudioSources))
  }

  function columnLevel(col) {
    if (!col || !col.node || !col.node.audio) return 0
    return col.kind === "master" ? outputVolume : level(col.node.audio)
  }

  function setColumnLevel(col, v) {
    if (!col) return
    if (col.kind === "master") setOutputVolume(v)
    else setLevel(col.node, v, col.kind === "stream" ? 1.5 : 1)
  }

  function columnMuted(col) {
    if (!col) return false
    if (col.kind === "master") return !anyAudible
    return !!(col.node && col.node.audio && col.node.audio.muted)
  }

  function toggleColumnMute(col) {
    if (!col) return
    if (col.kind === "master") toggleAllMuted()
    else if (col.node && col.node.audio) col.node.audio.muted = !col.node.audio.muted
  }

  // Sound alone (the speaker menu's Playback/Recording devices, `vistaaudio
  // sound`): Vista opened the Sound dialog by itself there; from the mixer's
  // device icon it opens over the mixer.
  property bool soundOnly: false
  onPropsOpenChanged: if (!propsOpen && soundOnly) closeMixer()

  function openMixer(withProps) {
    soundOnly = !!withProps
    mixerFocus = 0
    mixerOpen = true
    menuOpen = false
    if (opened) close()
    if (withProps) openProps()
  }

  function closeMixer() {
    soundOnly = false
    propsOpen = false
    mixerOpen = false
  }

  onMixerOpenChanged: {
    if (mixerOpen) refreshDisplayAudioModels()
    else clearDisplayAudioModels()
  }

  // `omarchy-shell vistaaudio mixer|sound`: the Volume Mixer, or the mixer
  // with the Sound dialog over it.
  IpcHandler {
    target: "vistaaudio"
    function mixer(): void { root.openMixer(false) }
    function sound(): void { root.openMixer(true) }
    function menu(): void { root.menuOpen = true }
  }

  // ---- Vista mixer and Sound dialog helpers -------------------------------
  // sndvol.exe.mui DIALOG 200 and mmsys.cpl.mui 110 are Segoe UI 9 / 8 pt:
  // vu/vv are the 9 pt dialog units (1.75 x 1.875 px); du/dv (8 pt) as before.
  function vu(x) { return Style.space(Math.round(x * 1.75)) }
  function vv(y) { return Style.space(Math.round(y * 1.875)) }
  readonly property var mixerMaster: shownColumns.length ? shownColumns[0] : null
  readonly property var mixerApps: shownColumns.filter(function(c) { return c.kind === "stream" })
  // mmsys.cpl's device icons by what the node says it is.
  function deviceIcon(node, recording) {
    var d = String((node && (node.description || node.nickname || node.name)) || "").toLowerCase()
    var id = recording ? 3014 : 3010
    if (/headset/.test(d)) id = 3015
    else if (/headphone/.test(d)) id = 3011
    else if (/hdmi|displayport|monitor/.test(d)) id = 3017
    else if (/mic/.test(d)) id = 3014
    return VistaScheme.graphics + "/mmsys/32/" + id + ".png"
  }
  function streamIcon(col) {
    var props = col && col.node && col.node.properties ? col.node.properties : {}
    var name = props["application.icon-name"] || props["application.process.binary"] || ""
    var path = name ? Quickshell.iconPath(String(name), true) : ""
    return path || (VistaScheme.graphics + "/sndvolsso/32/124.png")
  }

  // ---- Properties ---------------------------------------------------------
  readonly property var propsDevices: propsMode === "playback" ? displayAudioSinks : displayAudioSources

  function openProps() {
    propsMode = "playback"
    propsDevice = displayAudioSinks.indexOf(sink)
    propsHidden = JSON.parse(JSON.stringify(hiddenColumns))
    propsOpen = true
  }

  function setPropsMode(mode) {
    propsMode = mode
    propsDevice = propsDevices.indexOf(mode === "playback" ? sink : source)
  }

  function applyProps() {
    var dev = propsDevices[propsDevice]
    if (dev) {
      if (propsMode === "playback" && dev !== sink) setDefaultSink(dev)
      else if (propsMode === "recording" && dev !== source) setDefaultSource(dev)
    }
    persistHidden(propsHidden)
    propsOpen = false
  }

  // As stock clock's persistSettings: applied locally first, then written
  // to the entry. With no writable entry it stays session-only.
  function persistHidden(map) {
    var keys = []
    for (var k in map) if (map[k]) keys.push(k)
    keys.sort()
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    if (keys.length) entry.hiddenColumns = keys
    else delete entry.hiddenColumns
    if (JSON.stringify(entry) === JSON.stringify(root.settings)) return
    root.settings = entry
    var sh = root.bar ? root.bar.shell : null
    if (!sh || typeof sh.updateEntryInline !== "function")
      console.warn("ocko.vista-audio: no settings writer; hidden columns are session-only")
    else if (sh.updateEntryInline(root.moduleName, entry) === false)
      console.warn("ocko.vista-audio: shell refused the settings write for " + root.moduleName)
  }

  QtObject {
    id: mixerOwner
    function close() { root.closeMixer() }
  }

  QtObject {
    id: menuOwner
    function close() { root.menuOpen = false }
  }

  // ---- inline components (declared before use) ----------------------------

  // One ring of a 3-D edge: `lit` on the top and left, `dark` on the
  // bottom and right.
  component EdgeRing: Item {
    property color lit
    property color dark
    Rectangle { width: parent.width; height: 1; color: parent.lit }
    Rectangle { width: 1; height: parent.height; color: parent.lit }
    Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: parent.dark }
    Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: parent.dark }
  }

  // DS_MODALFRAME without a caption (the flyout): EDGE_RAISED -- 3DLight /
  // 3DDkShadow outside, 3DHighlight / 3DShadow inside -- on the face.
  component RaisedFrame: Rectangle {
    color: VistaScheme.sc.face
    EdgeRing { anchors.fill: parent; lit: "#F1EFE2"; dark: "#716F64" }
    EdgeRing { anchors.fill: parent; anchors.margins: 1; lit: "#FFFFFF"; dark: "#ACA899" }
  }

  // The mixctls_vumeter: ten chunks lit from the bottom by the input peak.
  // Rectangles, not a Canvas: the peak moves every frame.
  component PeakMeter: Rectangle {
    id: meter
    property real peak: 0
    color: "#FFFFFF"
    border.width: 1
    border.color: "#7F9DB9"
    Repeater {
      model: 10
      Rectangle {
        required property int index
        x: 2
        width: meter.width - 4
        height: (meter.height - 4) / 10 - 1
        y: meter.height - 2 - (index + 1) * (height + 1)
        color: "#2CC12C"
        visible: Math.round(Math.max(0, Math.min(1, meter.peak)) * 10) > index
      }
    }
  }

  // One sndvol32 column: template 101 for master, 102 for every other line.
  // A Volume Mixer column (64 DLU, DIALOG 200's Device controls): icon, name,
  // the vertical trackbar, and the mute button (the speaker glyph, crossed
  // while muted). The master's icon opens the Sound dialog.
  component VistaMixerColumn: Item {
    id: col
    property var info: null
    property int colIndex: 0
    readonly property bool master: !!info && info.kind === "master"
    readonly property var audio: info && info.node ? info.node.audio : null
    width: root.vu(64)
    height: root.vv(153)

    Rectangle {
      x: root.vu(17) - root.s(2); y: root.vv(13) - root.s(2)
      width: root.s(36); height: root.s(36)
      radius: root.s(3)
      visible: col.master && iconMouse.containsMouse
      color: "#E5F3FB"; border.color: "#70C0E7"
    }
    Image {
      x: root.vu(17); y: root.vv(13)
      width: root.s(32); height: root.s(32)
      source: col.master ? root.deviceIcon(root.volumeSink, false) : root.streamIcon(col.info)
      smooth: true; mipmap: true
      MouseArea { id: iconMouse; anchors.fill: parent; hoverEnabled: col.master; enabled: col.master; onClicked: root.openProps() }
    }
    Text {
      x: root.vu(4); y: root.vv(33)
      width: root.vu(56); height: root.vv(16)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: col.master ? (root.volumeSink ? root.vistaLabel(root.volumeSink, root.displayAudioSinks) : "Speakers") : root.columnCaption(col.info)
      color: "#000000"
      font.family: "Segoe UI"
      font.pixelSize: root.s(12)
    }
    VistaTrackbar {
      id: vol
      x: root.vu(17) + (root.vu(17) - width) / 2 - root.s(2)
      y: root.vv(51)
      height: root.vv(77)
      orientation: Qt.Vertical
      thumbStyle: "both"
      tickCount: 11
      to: col.info && col.info.kind === "stream" ? 1.5 : 1
      enabled: !!col.audio
      focused: root.mixerFocus === col.colIndex && !root.propsOpen
      value: root.columnLevel(col.info)
      onMoved: function(v) { root.setColumnLevel(col.info, v); root.mixerFocus = col.colIndex }
      HoverHandler { id: volHover }
    }
    Rectangle {
      x: root.vu(23) - root.s(2); y: root.vv(128)
      width: root.vu(17); height: root.vv(15)
      radius: root.s(2)
      color: muteMouse.containsMouse ? "#E5F3FB" : "transparent"
      border.color: muteMouse.containsMouse ? "#70C0E7" : "transparent"
      Image {
        anchors.centerIn: parent
        width: root.s(16); height: root.s(16)
        // the device's own mute (Vista muted the endpoint, not "everything")
        source: VistaScheme.graphics + "/sndvolsso/16/" + ((col.master ? root.outputMuted : root.columnMuted(col.info)) ? 120 : 124) + ".png"
      }
      MouseArea {
        id: muteMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: col.master ? root.hasOutput : !!col.audio
        onClicked: {
          if (col.master) root.toggleOutputMute()
          else root.toggleColumnMute(col.info)
          root.mixerFocus = col.colIndex
        }
      }
    }
    VistaToolTip {
      visible: volHover.hovered || vol.pressed
      x: Math.min(col.width - width - root.s(2), vol.x + vol.width)
      y: vol.y + (1 - vol.ratio) * vol.span - height / 2 + vol.thumbAlong / 2
      z: 10
      text: Math.round(vol.shown * 100) + "%"
    }
  }


  // ---- 1. the volume flyout -------------------------------------------------
  // Vista's (SndVolSSO): a narrow white flyout with the device's speaker icon,
  // the vertical trackbar, the mute button (the speaker glyph, crossed when
  // muted) and the link area with "Mixer".
  KeyboardPanel {
    id: flyoutPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: flyoutKeys
    gap: 0
    padding: 0
    borderSpec: Border.none()
    contentWidth: root.s(80)
    contentHeight: root.s(262)

    PanelKeyCatcher {
      id: flyoutKeys
      anchors.fill: parent
      Component.onCompleted: root.vistaBareCard(flyoutKeys)
      // k/l and Up/Right raise, j/h and Down/Left lower, as a vertical
      // trackbar with focus does.
      onMoveRequested: function(dx, dy) { root.nudgeOutput(dx !== 0 ? dx * 0.05 : -dy * 0.05) }
      onActivateRequested: root.toggleOutputMute()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "m" || t === "M") root.toggleOutputMute() }

      Rectangle {
        anchors.fill: parent
        color: "#FFFFFF"
        border.color: "#7A7A7A"
        radius: root.s(3)

        // The device: its speaker icon.
        Image {
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.s(14)
          width: root.s(32); height: root.s(32)
          source: VistaScheme.graphics + "/sndvolsso/32/" + (root.outputMuted ? 120 : 124) + ".png"
          smooth: true; mipmap: true
        }
        VistaTrackbar {
          id: flyTrack
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.s(56)
          height: root.s(130)
          orientation: Qt.Vertical
          thumbStyle: "both"
          enabled: root.hasOutput
          focused: true
          value: root.outputVolume
          onMoved: function(v) { root.setOutputVolume(v) }
          HoverHandler { id: flyHover }
        }
        // Mute: a flat button holding the speaker glyph.
        Rectangle {
          id: muteBtn
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.s(194)
          width: root.s(28); height: root.s(24)
          radius: root.s(2)
          color: muteMouse.containsMouse ? "#E5F3FB" : "transparent"
          border.color: muteMouse.containsMouse ? "#70C0E7" : "transparent"
          Image {
            anchors.centerIn: parent
            width: root.s(16); height: root.s(16)
            source: VistaScheme.graphics + "/sndvolsso/16/" + (root.outputMuted ? 120 : 124) + ".png"
            smooth: true
          }
          MouseArea {
            id: muteMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.hasOutput
            onClicked: root.toggleOutputMute()
          }
        }
        Rectangle {
          x: 1; y: parent.height - height - 1
          width: parent.width - 2; height: root.s(32)
          color: "#F0F0F0"
          Rectangle { width: parent.width; height: 1; color: "#DCDCDC" }
          Text {
            anchors.centerIn: parent
            text: "Mixer"
            color: "#0066CC"
            font.family: "Segoe UI"
            font.pixelSize: root.s(12)
            font.underline: mixMouse.containsMouse
            MouseArea {
              id: mixMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openMixer(false)
            }
          }
        }
      }

      // The value tip: Vista showed the speaker's name and level on hover.
      VistaToolTip {
        visible: root.opened && (flyHover.hovered || flyTrack.pressed || root.tipFlash)
        x: parent.width - width
        y: -height - root.s(2)
        text: "Speakers: " + Math.round(flyTrack.shown * 100) + "%" + (root.outputMuted ? " (muted)" : "")
      }
    }
  }

  // ---- 2. the speaker's context menu ---------------------------------------
  KeyboardPanel {
    id: menuPanel
    anchorItem: button
    owner: menuOwner
    bar: root.bar
    open: root.menuOpen
    focusTarget: menuKeys
    gap: 0
    padding: 0
    borderSpec: Border.none()
    contentWidth: ctxMenu.implicitWidth
    contentHeight: ctxMenu.implicitHeight
    onOpenChanged: ctxMenu.currentIndex = -1

    PanelKeyCatcher {
      id: menuKeys
      anchors.fill: parent
      Component.onCompleted: root.vistaBareCard(menuKeys)
      onMoveRequested: function(dx, dy) { if (dy !== 0) ctxMenu.moveBy(dy) }
      onActivateRequested: ctxMenu.activateCurrent()
      onCloseRequested: root.menuOpen = false

      VistaMenu {
        id: ctxMenu
        anchors.fill: parent
        items: [
          { text: "Open Volume <u>M</u>ixer", bold: true },
          { separator: true },
          { text: "<u>P</u>layback devices" },
          { text: "<u>R</u>ecording devices" },
          { text: "<u>S</u>ounds", enabled: false }
        ]
        // Vista's speaker menu: the mixer, or the Sound dialog on its tab.
        onTriggered: function(i) {
          root.openMixer(i === 2 || i === 3)
          if (i === 3) root.setPropsMode("recording")
        }
      }
    }
  }

  // ---- 3. the "Volume Control" window --------------------------------------
  KeyboardPanel {
    id: mixerPanel
    anchorItem: button
    owner: mixerOwner
    bar: root.bar
    open: root.mixerOpen
    focusTarget: mixerKeys
    padding: 0
    borderSpec: Border.none()
    readonly property real naturalWidth: root.vu(71 + 6) + Math.max(root.vu(193), root.mixerApps.length * root.vu(64) + root.vu(4)) + 2 * mixerWin.frameWidth
    contentWidth: mixerPanel.fittedContentWidth(naturalWidth)
    contentHeight: root.s(29) + root.vv(166) + mixerWin.frameWidth

    PanelKeyCatcher {
      id: mixerKeys
      anchors.fill: parent
      property string menuName: ""
      Component.onCompleted: root.vistaBareCard(mixerKeys)
      onMoveRequested: function(dx, dy) {
        if (root.propsOpen) {
          if (dy !== 0 && root.propsDevices.length)
            root.propsDevice = Math.max(0, Math.min(root.propsDevices.length - 1, root.propsDevice + dy))
          else if (dx !== 0) root.setPropsMode(root.propsMode === "playback" ? "recording" : "playback")
          return
        }
        if (dx !== 0) root.mixerFocus = Math.max(0, Math.min(root.shownColumns.length - 1, root.mixerFocus + dx))
        else {
          var c = root.shownColumns[root.mixerFocus]
          root.setColumnLevel(c, root.columnLevel(c) - dy * 0.05)
        }
      }
      onActivateRequested: {
        if (root.propsOpen) root.applyProps()
        else root.toggleColumnMute(root.shownColumns[root.mixerFocus])
      }
      onCloseRequested: {
        if (menuName !== "") menuName = ""
        else if (root.propsOpen) root.propsOpen = false
        else root.closeMixer()
      }
      onTabRequested: function(direction) {
        if (root.propsOpen || root.shownColumns.length === 0) return
        root.mixerFocus = (root.mixerFocus + direction + root.shownColumns.length) % root.shownColumns.length
      }
      onTextKey: function(t) {
        if ((t === "m" || t === "M") && !root.propsOpen) root.toggleColumnMute(root.shownColumns[root.mixerFocus])
      }

      // sndvol.exe's Volume Mixer (DIALOG 200): the Device group (the default
      // output) and the Applications group (one column per playing stream).
      // The device icon opens the Sound dialog, as in Vista.
      VistaWindow {
        id: mixerWin
        anchors.fill: parent
        visible: !root.soundOnly
        title: "Volume Mixer - " + (root.volumeSink ? root.vistaLabel(root.volumeSink, root.displayAudioSinks) : "Speakers")
        titleIcon: VistaScheme.graphics + "/sndvol/16/101.png"
        buttons: ["min", "close"]
        active: !root.propsOpen
        onMinimizeClicked: root.closeMixer()
        onCloseClicked: root.closeMixer()

        VistaGroupBox { x: root.vu(6); y: root.vv(6); width: root.vu(64); height: root.vv(153); caption: "Device" }
        VistaMixerColumn { x: root.vu(6); y: root.vv(6); info: root.mixerMaster; colIndex: 0 }

        VistaGroupBox {
          x: root.vu(71); y: root.vv(6)
          width: Math.max(root.vu(193), appsRow.width + root.vu(4)); height: root.vv(153)
          caption: "Applications"
        }
        Row {
          id: appsRow
          x: root.vu(73); y: root.vv(6)
          Repeater {
            model: root.mixerOpen ? root.mixerApps.length : 0
            VistaMixerColumn {
              required property int index
              info: root.mixerApps[index]
              colIndex: index + 1
            }
          }
        }
      }

      // ---- Sound (mmsys.cpl: Playback 110 / Recording 111), over the mixer -
      // Blocks the mixer while open, as a modal dialog does.
      MouseArea {
        anchors.fill: parent
        visible: root.propsOpen
        z: 30
      }
      VistaPropertySheet {
        id: propsWin
        nested: true
        visible: root.propsOpen
        z: 31
        x: Math.max(-mixerPanel.cardOrigin.x, Math.min((parent.width - width) / 2, mixerPanel.screenW - mixerPanel.cardOrigin.x - width))
        y: parent.height - height
        title: "Sound"
        buttons: ["close"]
        onCloseClicked: root.propsOpen = false
        titles: ["Playback", "Recording"]
        tab: root.propsMode === "playback" ? 0 : 1
        onTabClicked: function(i) { root.setPropsMode(i === 0 ? "playback" : "recording") }
        pageWidth: root.du(252)
        pageHeight: root.dv(218)
        buttonLabels: ["OK", "Cancel", "<u>A</u>pply"]
        onButtonClicked: function(i) {
          if (i === 1) root.propsOpen = false
          else root.applyProps()
        }

        Item {
          parent: propsWin.page
          anchors.fill: parent
          VistaLabel {
            x: root.du(7); y: root.dv(7)
            text: root.propsMode === "playback" ? "Select a playback device below to modify its settings:"
              : "Select a recording device below to modify its settings:"
          }
          // SysListView32 (7,21 238x171): icon, name, "Default Device".
          Rectangle {
            x: root.du(7); y: root.dv(21)
            width: root.du(238); height: root.dv(171)
            color: "#FFFFFF"
            border.width: 1
            border.color: VistaScheme.sc.edit
            clip: true
            Column {
              x: 1; y: 1
              width: parent.width - 2
              Repeater {
                model: root.propsOpen ? root.propsDevices.length : 0
                Item {
                  id: devRow
                  required property int index
                  readonly property var node: root.propsDevices[index]
                  readonly property bool chosen: root.propsDevice === index
                  readonly property bool isDefault: node === (root.propsMode === "playback" ? root.sink : root.source)
                  width: parent.width
                  height: root.s(46)
                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.s(2)
                    visible: devRow.chosen || devMouse.containsMouse
                    radius: root.s(2)
                    border.color: devRow.chosen ? "#7DA2CE" : "#B8D6FB"
                    gradient: Gradient {
                      GradientStop { position: 0; color: devRow.chosen ? "#DCEBFC" : "#FAFBFD" }
                      GradientStop { position: 1; color: devRow.chosen ? "#C1DBFC" : "#EBF3FD" }
                    }
                  }
                  Image {
                    x: root.s(8); anchors.verticalCenter: parent.verticalCenter
                    width: root.s(32); height: root.s(32)
                    source: root.deviceIcon(devRow.node, root.propsMode !== "playback")
                    smooth: true
                    // the default device's green check
                    Rectangle {
                      visible: devRow.isDefault
                      anchors.right: parent.right; anchors.bottom: parent.bottom
                      width: root.s(14); height: root.s(14)
                      radius: width / 2
                      color: "#2E9E2E"; border.color: "#FFFFFF"
                      Text { anchors.centerIn: parent; text: "\u2713"; color: "white"; font.pixelSize: root.s(10); font.bold: true }
                    }
                  }
                  Column {
                    x: root.s(48); anchors.verticalCenter: parent.verticalCenter
                    VistaLabel { text: root.friendlyDeviceLabel(devRow.node.description || root.nodeLabel(devRow.node)); textFormat: Text.PlainText }
                    VistaLabel { text: devRow.isDefault ? "Default Device" : "Working"; color: "#575757" }
                  }
                  MouseArea {
                    id: devMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.propsDevice = devRow.index
                    onDoubleClicked: { root.propsDevice = devRow.index; root.applyProps() }
                  }
                }
              }
            }
          }
          VistaButton { x: root.du(7); y: root.dv(199); width: root.du(50); height: root.dv(14); text: "<u>C</u>onfigure"; enabled: false }
          VistaButton {
            x: root.du(131); y: root.dv(199); width: root.du(60); height: root.dv(14)
            text: "<u>S</u>et Default"
            enabled: root.propsDevice >= 0
            onClicked: {
              var dev = root.propsDevices[root.propsDevice]
              if (root.propsMode === "playback") root.setDefaultSink(dev)
              else root.setDefaultSource(dev)
            }
          }
          VistaButton { x: root.du(195); y: root.dv(199); width: root.du(50); height: root.dv(14); text: "<u>P</u>roperties"; enabled: false }
        }
      }
    }
  }
}
