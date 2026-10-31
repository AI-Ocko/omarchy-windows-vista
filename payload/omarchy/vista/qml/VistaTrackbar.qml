import QtQuick
import qs.Commons

// VistaTrackbar: [TrackBar.*] of the active scheme. The track is sliderTrack
// (SizingMargins 2) 4 px thick, the thumb one of the 96-dpi thumb bitmaps
// (5 frames: normal, hot, pressed, focused, disabled), tics in
// [TrackBar.Tics] 161 161 146. A vertical trackbar puts `to` at the top, as
// Vista's volume sliders do. Like PanelSlider it never writes `value` itself:
// it emits moved(v) and shows the drag position until the owner catches up,
// so a `value:` binding to live state survives.
Item {
  id: tb

  property string artDir: VistaScheme.artDir
  property int orientation: Qt.Horizontal
  // "both" (the rectangular TBS_BOTH thumb), or the way the pointer faces:
  // "down"/"up" when horizontal, "left"/"right" when vertical.
  property string thumbStyle: orientation === Qt.Horizontal ? "down" : "left"
  property real from: 0
  property real to: 1
  property real value: 0
  property real stepSize: 0.05
  property real pageSize: (to - from) / 5
  property int tickCount: 0
  property bool focused: false
  readonly property bool pressed: mouse.dragging
  signal moved(real value)

  readonly property bool vertical: orientation === Qt.Vertical
  // Thumb at 96 dpi: 11 x 21 along a horizontal track, 21 x 11 along a vertical one.
  readonly property real thumbAlong: Style.space(11)
  readonly property real thumbAcross: Style.space(21)
  readonly property real span: Math.max(0, (vertical ? height : width) - thumbAlong)
  property real dragValue: value
  readonly property real shown: mouse.dragging ? dragValue : value
  readonly property real ratio: to > from ? Math.max(0, Math.min(1, (shown - from) / (to - from))) : 0

  // Room across the track for the thumb, plus tics beside it when shown.
  readonly property real across: Style.space(tickCount > 1 ? 30 : 26)
  implicitWidth: vertical ? across : Style.space(120)
  implicitHeight: vertical ? Style.space(120) : across

  function clampStep(v) {
    if (stepSize > 0) v = from + Math.round((v - from) / stepSize) * stepSize
    return Math.max(from, Math.min(to, v))
  }
  function setTo(v) { v = clampStep(v); dragValue = v; moved(v) }
  function increase() { setTo(value + stepSize) }
  function decrease() { setTo(value - stepSize) }
  function valueAt(px, py) {
    var r = span > 0 ? ((vertical ? py : px) - thumbAlong / 2) / span : 0
    r = Math.max(0, Math.min(1, r))
    return from + (vertical ? 1 - r : r) * (to - from)
  }

  // Track, centred across the thumb, inset half a thumb at each end.
  VistaArt {
    x: tb.vertical ? (tb.width - width) / 2 : tb.thumbAlong / 2
    y: tb.vertical ? tb.thumbAlong / 2 : (tb.height - height) / 2
    width: tb.vertical ? Style.space(4) : tb.span
    height: tb.vertical ? tb.span : Style.space(4)
    source: tb.artDir + "/trk-track.png"
    margins: [2, 2, 2, 2]
  }

  // Tics on the side the pointer faces (both sides for the plain thumb).
  Repeater {
    model: tb.tickCount > 1 ? tb.tickCount * (tb.thumbStyle === "both" ? 2 : 1) : 0
    Rectangle {
      required property int index
      readonly property int i: index % tb.tickCount
      readonly property bool before: tb.thumbStyle === "up" || tb.thumbStyle === "left"
                                     || (tb.thumbStyle === "both" && index >= tb.tickCount)
      readonly property real along: tb.thumbAlong / 2 + tb.span * i / (tb.tickCount - 1)
      readonly property real across: before ? (tb.vertical ? tb.width : tb.height) / 2 - tb.thumbAcross / 2 - Style.space(4)
                                            : (tb.vertical ? tb.width : tb.height) / 2 + tb.thumbAcross / 2 + Style.space(1)
      x: tb.vertical ? across : along
      y: tb.vertical ? along : across
      width: tb.vertical ? Style.space(3) : 1
      height: tb.vertical ? 1 : Style.space(3)
      color: "#A1A192"
    }
  }

  Image {
    id: thumb
    readonly property int frame: !tb.enabled ? 4 : mouse.dragging ? 2 : mouse.overThumb ? 1 : tb.focused ? 3 : 0
    readonly property string kind: tb.thumbStyle === "both" ? (tb.vertical ? "v" : "h") : tb.thumbStyle
    width: tb.vertical ? tb.thumbAcross : tb.thumbAlong
    height: tb.vertical ? tb.thumbAlong : tb.thumbAcross
    x: tb.vertical ? (tb.width - width) / 2 : tb.ratio * tb.span
    y: tb.vertical ? (1 - tb.ratio) * tb.span : (tb.height - height) / 2
    source: tb.artDir + "/trk-thumb-" + kind + "-" + frame + ".png"
    smooth: true
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: tb.enabled
    property bool dragging: false
    property real grab: 0
    readonly property bool overThumb: containsMouse && mouseX >= thumb.x && mouseX < thumb.x + thumb.width
                                      && mouseY >= thumb.y && mouseY < thumb.y + thumb.height
    onPressed: function(m) {
      if (overThumb) {
        // Keep the grab point under the pointer, as Vista does.
        grab = tb.vertical ? m.y - (thumb.y + thumb.height / 2) : m.x - (thumb.x + thumb.width / 2)
        tb.dragValue = tb.value
        dragging = true
      } else {
        // A click on the track pages toward the click, as Vista does.
        var target = tb.valueAt(m.x, m.y)
        tb.setTo(target > tb.value ? Math.min(target, tb.value + tb.pageSize) : Math.max(target, tb.value - tb.pageSize))
      }
    }
    onPositionChanged: function(m) {
      if (dragging) tb.setTo(tb.valueAt(m.x - (tb.vertical ? 0 : grab), m.y - (tb.vertical ? grab : 0)))
    }
    onReleased: dragging = false
    onCanceled: dragging = false
    onWheel: function(w) {
      if (w.angleDelta.y > 0) tb.increase()
      else if (w.angleDelta.y < 0) tb.decrease()
    }
  }
}
