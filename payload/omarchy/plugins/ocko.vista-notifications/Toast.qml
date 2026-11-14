// ocko.vista-notifications: omarchy.notifications 4.5.0 Toast.qml drawn as a
// Windows Vista balloon tip. The interface (inputs, targetHeight, signals),
// the lifetime timer, the buttons (DeedButton), redaction and the body's
// StyledText from Markup are stock 4.5.0; only the marked "Vista:" blocks
// change the look:
//   * the plate is a VistaBalloon (white to #E4E5F0, grey edge); the front
//     card of the newest deck (lowest on screen) gets the tail, which hangs
//     below the card into the strip Service.qml keeps above the taskbar, so
//     the tail never changes the card's measured height;
//   * user32's information / warning / error icon before the title (urgent,
//     or an error/warn app icon), Segoe UI title in the main-instruction blue,
//     black body text, blue links;
//   * the balloon close button (Tooltip.Close art, 3 frames) always shown,
//     hot-tracked from the deck's hover input (card.pointerOver);
//   * no Nerd glyphs or letter tiles (Vista has none; the icon stands in);
//     only the sender's own picture is drawn beside the text.
// Hover is an input (the deck owns it), as stock.

// One notification card. Layout.js decides where it goes and the scene animates
// it there; the card owns only what happens inside its own edges.

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

import "Security.js" as Security
import "Delivery.js" as Delivery
import "Store.js" as Store
import "Icons.js" as Icons
import "../../vista/qml"                                     // Vista: VistaBalloon, VistaScheme

Item {
  id: card

  property var row: ({})
  property var place: ({ y: 0, scale: 1, opacity: 1, z: 1, front: true, hidden: false })
  property var scene: null                   // owns the clock; without it the card stands still
  property bool expanded: false
  property bool sole: false                  // the only card on screen
  property bool paused: false
  property bool hovered: false
  property bool selected: false              // the keyboard's card
  property double now: Date.now()
  property real cardWidth: Style.space(380)
  property var actions: []                   // what the sender put on the wire

  // The pointer in the deck's coordinates: the deck owns hover, so cards and
  // their buttons work out what is under it themselves.
  property real hoverX: -1
  property real hoverY: -1
  readonly property real localHoverX: hoverX - x
  readonly property real localHoverY: hoverY - y

  function pointerOver(item) {
    if (!hovered) return false
    var origin = item.mapToItem(card, 0, 0)
    return localHoverX >= origin.x && localHoverX <= origin.x + item.width
        && localHoverY >= origin.y && localHoverY <= origin.y + item.height
  }

  // Nothing while it is fresh, then minutes, then the clock time, then
  // "yesterday", then the day.
  function ago() {
    var t = Number(row.ts || 0) * 1000
    if (!t) return ""
    var s = Math.max(0, (now - t) / 1000)
    if (s < 300) return ""
    if (s < 3600) return I18n.t("notifications.minutesAgo").arg(I18n.formatNumber(Math.round(s / 60)))
    var then = new Date(t)
    var locale = Qt.locale(I18n.formatLocale)
    var sameDay = new Date(now).toDateString() === then.toDateString()
    if (sameDay) return locale.toString(then, "HH:mm")
    var yest = new Date(now - 86400000).toDateString() === then.toDateString()
    if (yest) return I18n.t("notifications.yesterday")
    return locale.toString(then, "ddd")
  }

  // The card's only duration: crossfades inside its own edges.
  readonly property int fade: Style.duration(150)

  signal expired()
  signal activated()
  signal dismissed()
  signal codeCopied(string code)
  signal actionInvoked(string identifier)
  signal execInvoked(int index)
  signal linkOpened()

  readonly property bool critical: row.urgency === 2
  // ==================================================== Vista: colours and icon
  // Fixed Vista balloon colours instead of the theme's notification colours
  // (the Vista themes' foreground is light grey, unreadable on the balloon).
  readonly property color dimColor: VistaScheme.sc.gray
  readonly property color bodyColor: VistaScheme.infoText
  readonly property color vistaTitleColor: VistaScheme.sc.instruction
  // The balloon's system icon: urgent, or an app icon naming an error or a
  // warning; otherwise information. row.appIcon is a bare theme name by now.
  readonly property string vistaIconKind: critical ? "warning"
    : (/error|fail/i.test(String(row.appIcon || "")) ? "error"
    : (/warn/i.test(String(row.appIcon || "")) ? "warning" : "info"))
  // The tail points at the notification area from the lowest card only: the
  // front card of the newest deck (Layout.js stands the deck on the taskbar),
  // or the last card on its way out.
  readonly property bool vistaTail: place.leaving
    ? place.front === true
    : !!(scene && scene.layout && scene.layout.decks.length > 0
         && String(scene.layout.decks[0].rows[0].key) === String(row.key))
  // ==================================================== end Vista
  readonly property color accentColor: critical ? Commons.Color.urgent
                                               : (row.urgency === 0 ? dimColor : Commons.Color.notifications.countdown)
  readonly property bool hasBody: String(row.body || "").length > 0
  readonly property bool redacted: Store.redacted(row)
  // Omarchy's own toasts and bare notify-send calls name no source worth a
  // letter, and a summary that opens with its own glyph already has its mark.
  readonly property bool anonymous: row.app === "omarchy-action" || row.app === "notify-send"
  readonly property bool glyphLed: Delivery.summaryStartsWithGlyph(row.summary)
  readonly property real contentPaddingY: hasBody ? Style.space(10) : Style.space(7)
  // A card behind the front of a collapsed deck is a shape: the cards are
  // translucent, so its text would read through the one in front. The text
  // fades as the deck moves (opening, closing, a card arriving over it or
  // leaving it the front) and jumps with it when a keypress skips the move.
  // It goes out in half the time it comes in, so a card arriving over this one
  // doesn't show both texts at once.
  property real contentOpacity: expanded || place.front ? 1 : 0
  Behavior on contentOpacity {
    id: contentFade
    enabled: !(card.scene && card.scene.jumping)
    NumberAnimation {
      duration: contentFade.targetValue > 0 ? card.fade : card.fade / 2
      easing.type: Easing.OutCubic
    }
  }

  // The body opens in an open deck, or on hover when nothing else is on
  // screen. Never in a collapsed stack: every card there is drawn at the front
  // one's height, so a tall one would hang out of it.
  readonly property bool bodyOpen: expanded || (hovered && sole)
  readonly property int bodyLines: bodyOpen ? 8 : 2

  // Every code the body carried; two or more have to say which they copy.
  readonly property var foundCodes: {
    var all = String(row.codes || row.code || "").split(" ")
    var out = []
    for (var i = 0; i < all.length; i++) if (all[i]) out.push(all[i])
    return out
  }

  // Buttons an Omarchy sender asked for (--action), as commands the shell runs.
  readonly property var execActions: Security.parseExecActions(row.execActions) || []

  // Every button, in Delivery.deeds' order, with the code labels translated.
  readonly property var allDeeds: {
    var out = Delivery.deeds(row, actions)
    for (var i = 0; i < out.length; i++)
      if (out[i].kind === "code")
        out[i].label = foundCodes.length > 1 ? I18n.t("notifications.copyThisCode").arg(out[i].value)
                                             : I18n.t("notifications.copyCode")
    return out
  }

  // Marks on the headline. Buttons say for themselves that a card can be
  // acted on; a verification code is marked even where they are hidden.
  readonly property var marks: {
    var out = []
    if (String(row.code || "")) out.push("\u{f0306}")
    return out
  }

  function doDeed(deed) {
    var kind = String(deed.kind || "")
    if (kind === "action") { actionInvoked(String(deed.value)); return }
    if (kind === "exec") { execInvoked(Number(deed.value)); return }
    codeCopied(String(deed.value))
    copiedCode = String(deed.value)
    tick.restart()
  }

  // The code last copied, ticked for a moment: copying is silent.
  property string copiedCode: ""
  Timer { id: tick; interval: 1400; onTriggered: card.copiedCode = "" }

  // Pausing holds the remaining time rather than restarting it.
  // An update (replaces_id) rewrites the row in place with a new arrival
  // time, and gets a fresh display period of its own duration. Its picture
  // may be new at the same path, so the image is read again too.
  property real remaining: Number(row.duration || 0)
  readonly property bool ticking: Number(row.duration || 0) > 0 && !paused
  readonly property string arrival: String(row.ts) + ":" + String(row.duration)
  property bool reloading: false
  onArrivalChanged: {
    remaining = Number(row.duration || 0)
    thumb.failed = 0
    reloading = true
    Qt.callLater(function() { card.reloading = false })
  }

  // Coarse: nothing draws the time left, only the expiry needs it.
  Timer {
    interval: 500
    repeat: true
    running: card.ticking && card.remaining > 0
    onTriggered: {
      card.remaining -= interval
      if (card.remaining <= 0) card.expired()
    }
  }

  width: cardWidth
  height: body.height

  LayoutMirroring.enabled: Commons.I18n.rightToLeft
  LayoutMirroring.childrenInherit: true

  // ---------------------------------------------------- what the scene reads
  //
  // Summed explicitly rather than taken from the laid-out height minus the
  // action area: that area's height derives from the card's, so subtracting it
  // back out is a binding loop. hasBody, not bodyBox.visible: Item.visible
  // includes ancestors, and an inactive output must not shrink the measurement.
  readonly property real textBlock:
      headline.height + (hasBody ? column.spacing + bodyBox.height : 0)

  // The same block at its two-line height: the icon is centred on this so a
  // body opening on hover does not walk it down the card.
  readonly property real restingBlock:
      headline.height + (hasBody ? column.spacing + bodyBox.restHeight : 0)

  // A block shorter than the mark is centred against it, measured at rest.
  readonly property real textOffset: Math.max(0, (thumb.height - restingBlock) / 2)

  readonly property real fixedHeight: plate.borderTop + plate.borderBottom
      + contentPaddingY * 2 + Math.max(thumb.height, textOffset + textBlock)

  // The height this card's *state* implies, a step function the deck lays out
  // from. Feeding a mid-animation height back into the layout stalls the stack.
  readonly property real targetHeight: fixedHeight + deedArea.wanted

  // The height the scene says it is right now, on the way there.
  property real drawnHeight: targetHeight


  y: scene ? scene.at(row.key, "y") : 0
  z: place.z
  scale: scene ? scene.at(row.key, "scale") : 1
  opacity: place.hidden ? 0 : (scene ? scene.at(row.key, "opacity") : 1)
  transformOrigin: Item.Top

  // `visible` is deliberately unbound: anything derived from layout output
  // (opacity, place.hidden) closes a binding loop through `heights`. A hidden
  // card is at opacity 0 and costs no drawing; `enabled` refuses the pointer.
  enabled: !place.hidden && !place.leaving

  // BorderSurface keeps gradients and per-side border widths; content below is
  // inset by those exact widths.
  // ==================================================== Vista: the balloon
  // In place of the BorderSurface: a VistaBalloon over the card, its tail (on
  // the lowest card) hanging below the card's own height. It exposes the
  // insets the stock layout reads off the plate: a 1 px edge all round.
  VistaBalloon {
    id: plate
    readonly property real borderTop: Math.max(1, Style.space(1))
    readonly property real borderBottom: borderTop
    readonly property real borderLeft: borderTop
    readonly property real borderRight: borderTop
    readonly property real contentTopInset: borderTop
    readonly property real contentLeftInset: borderTop
    readonly property real contentRightInset: borderTop
    width: body.width
    height: body.height + tailHeight
    showTail: card.vistaTail
    tailDown: true
    // Vista's tail aims a little left of the balloon's right edge, at the
    // tray icons left of the clock.
    tailX: width - Style.space(52)
  }

  // The keyboard's card is tinted with Vista's selection blue, buttons and
  // all, inside the balloon's edge (not over the tail).
  Rectangle {
    anchors.fill: body
    anchors { leftMargin: plate.borderLeft; rightMargin: plate.borderRight
              topMargin: plate.borderTop; bottomMargin: plate.borderBottom }
    visible: card.selected
    radius: plate.radius
    color: Qt.rgba(0.2, 0.6, 1.0, 0.15)
  }
  // ==================================================== end Vista

  Item {
    id: body
    width: parent.width
    height: card.drawnHeight

    Row {
      id: layout
      // Top-anchored: centred content would slide up as the card grows.
      anchors { left: parent.left; right: parent.right; top: parent.top
                leftMargin: plate.contentLeftInset + Style.space(12)
                rightMargin: plate.contentRightInset + Style.space(12)
                topMargin: plate.contentTopInset + card.contentPaddingY }
      spacing: thumb.compact ? Style.space(8) : Style.space(12)

      // The sender's image, else the icon resolved for its source, else the
      // glyph an Omarchy sender asked for, else the first letter of the source.
      Item {
        id: thumb
        readonly property bool pictured: picture.status === Image.Ready && best !== ""
        // Vista: no Nerd glyph and no letter tile; the title's system icon stands in.
        readonly property bool glyphed: false
        readonly property bool lettered: false
        // A one-line toast keeps its glyph at text size beside the line.
        readonly property bool compact: glyphed && !card.hasBody
        readonly property real slot: Style.space(40)
        width: pictured || lettered ? slot : glyphed ? (compact ? glyphText.implicitWidth : slot) : 0
        height: width > 0 ? (compact ? glyphText.implicitHeight : slot) : 0
        visible: width > 0
        y: Math.max(0, (card.restingBlock - height) / 2)
        opacity: card.contentOpacity

        function entryIcon(icon) {
          var value = String(icon || "")
          return value.charAt(0) === "/" ? Util.fileUrl(value) : value ? Quickshell.iconPath(value, true) : ""
        }

        // Only what the sender handed over and what is installed for its source:
        // Quickshell.iconPath answers "" for a missing icon when asked to check,
        // where a bare image://icon/ URL would draw a checkerboard.
        readonly property string sent: /^image:\/\/qsimage\/[0-9]+\/[0-9]+$/.test(String(card.row.image || ""))
                                       ? String(card.row.image) : Security.localImageUrl(card.row.image)

        // Best first: the sender's picture, then the icon theme, then a
        // desktop entry's icon (Icons.candidates has the names). A file that will not load gives way to the next.
        function firstOf(names, look) {
          for (var i = 0; i < names.length; i++) {
            var found = look(names[i])
            if (found) return found
          }
          return ""
        }
        // Vista: only the sender's own picture (album art, a screenshot), as
        // Vista's balloons drew no app icon; `sent` is stock's policy-checked URL.
        readonly property var sources: sent ? [sent] : []
        readonly property string sourcesKey: sources.join("\n")
        property int failed: 0
        onSourcesKeyChanged: failed = 0
        readonly property string best: sources[failed] || ""
        readonly property bool photo: best !== "" && best === sent
        readonly property bool mono: !photo && Icons.isSymbolic(best)

        Rectangle {
          anchors.fill: parent
          visible: thumb.lettered
          radius: Style.cornerRadius
          color: Style.normalFillFor(Commons.Color.notifications.text, card.accentColor, Commons.Color.urgent)

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: String(card.row.source || card.row.app || "?").substring(0, 1).toUpperCase()
            color: card.dimColor
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
          }
        }

        Text {
          id: glyphText
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: thumb.glyphed
          text: String(card.row.glyph || "")
          color: Commons.Color.notifications.text
          font.family: Delivery.omarchyGlyph(card.row.glyph) ? "omarchy" : Style.font.family
          font.pixelSize: (thumb.compact ? Style.font.icon : Style.font.displayLarge)
        }

        Image {
          id: picture
          anchors.fill: parent
          visible: thumb.pictured
          source: card.reloading ? "" : thumb.best
          onStatusChanged: if (status === Image.Error && thumb.failed < thumb.sources.length) thumb.failed += 1
          // A photo fills its square; an app icon keeps its own shape.
          fillMode: thumb.photo ? Image.PreserveAspectCrop : Image.PreserveAspectFit
          // Constant, so the slot resizing never reloads the image.
          sourceSize.width: thumb.slot * Screen.devicePixelRatio
          sourceSize.height: thumb.slot * Screen.devicePixelRatio
          asynchronous: true
          // A sender may write each picture to the same path (cover art, say).
          cache: !(thumb.photo && thumb.best.indexOf("file:") === 0)
          // A one-colour icon is brightened to a silhouette and tinted with the
          // theme's text colour, keeping its anti-aliased edge. A photo is
          // rounded like the card, only when the theme rounds at all.
          readonly property bool rounded: thumb.photo && Style.cornerRadius > 0
          opacity: thumb.mono ? 0.85 : 1
          layer.enabled: visible && (thumb.mono || rounded)
          layer.effect: MultiEffect {
            maskEnabled: picture.rounded
            maskSource: mask
            brightness: thumb.mono ? 1.0 : 0.0
            colorization: thumb.mono ? 1.0 : 0.0
            colorizationColor: Commons.Color.notifications.text
          }
        }

        Rectangle {
          id: mask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          radius: Style.cornerRadius
          color: "black"
        }
      }

      Column {
        id: column
        y: card.textOffset
        width: layout.width - (thumb.visible ? thumb.width + layout.spacing : 0)
        spacing: Style.space(3)

        // Title, marks, and when it arrived.
        Item {
          id: headline
          width: parent.width
          height: Math.max(title.implicitHeight, rightSide.height)
          opacity: card.contentOpacity

          // ================================================ Vista: title
          // user32's 16 px information / warning / error icon, then the title
          // in Segoe UI 12 pt, Vista's main-instruction blue, not bold.
          Image {
            id: vistaIcon
            anchors.left: parent.left
            anchors.verticalCenter: title.verticalCenter
            width: Style.space(16)
            height: Style.space(16)
            source: VistaScheme.sysIcon(card.vistaIconKind, 16)
            smooth: true
          }

          Text {
            textFormat: Text.PlainText
            id: title
            anchors.left: vistaIcon.right
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, parent.width - rightSide.width
                   - vistaIcon.width - Style.space(6)
                   - (titleMarks.visible ? titleMarks.width + Style.space(7) : 0)
                   - Style.space(8))
            text: card.redacted ? I18n.t("notifications.redactedSummary") : String(card.row.summary || "")
            color: card.vistaTitleColor
            font.family: "Segoe UI"
            font.pixelSize: Style.space(16)
            // ================================================ end Vista
            wrapMode: Text.Wrap
            maximumLineCount: card.bodyOpen ? 8 : 3
            elide: Text.ElideRight
          }

          Row {
            id: titleMarks
            visible: card.marks.length > 0
            anchors.verticalCenter: title.verticalCenter
            // Placed by arithmetic, so it follows a right-to-left card itself.
            readonly property real titleInk: Math.min(title.implicitWidth, title.width)
            x: card.LayoutMirroring.enabled
               ? title.x + title.width - titleInk - Style.space(7) - width
               : title.x + titleInk + Style.space(7)
            spacing: Style.space(5)

            Repeater {
              model: card.marks
              Text {
                textFormat: Text.PlainText
                required property var modelData
                text: modelData
                color: card.vistaTitleColor                  // Vista
                opacity: 0.9
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }

          Row {
            id: rightSide
            anchors.right: parent.right
            anchors.verticalCenter: title.verticalCenter
            spacing: Style.space(5)

            // ============================================ Vista: close button
            // Vista's balloon close button is always there, so the time sits
            // beside it rather than crossfading with it. Hot from the deck's
            // hover input (pointerOver), pressed from its own click area.
            Text {
              textFormat: Text.PlainText
              id: stamp
              anchors.verticalCenter: parent.verticalCenter
              text: card.ago()
              visible: text !== ""
              color: card.dimColor
              font.family: "Segoe UI"
              font.pixelSize: Style.font.bodySmall
            }

            Item {
              id: shut
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(17)
              height: Style.space(16)
              readonly property bool hot: card.pointerOver(shut)

              Image {
                anchors.fill: parent
                source: VistaScheme.art("balloon-close-" + (shutArea.pressed ? 2 : shut.hot ? 1 : 0))
                smooth: true
              }

              MouseArea {
                id: shutArea
                anchors.fill: parent
                anchors.margins: -Style.space(3)
                cursorShape: Qt.PointingHandCursor
                onClicked: card.dismissed()
              }
            }
            // ============================================ end Vista
          }
        }

        FontMetrics {
          id: metrics
          font.family: "Segoe UI"                             // Vista: the body's font
          font.pixelSize: Style.font.bodySmall                // Vista
        }

        // StyledText, not RichText: it covers the tags Markup lets through,
        // keeps links clickable, and can still end a long body in an ellipsis.
        Text {
          id: bodyBox
          width: parent.width
          // The closed height, read only by the icon so it does not move.
          readonly property real restHeight: Math.ceil(Math.max(1, metrics.height) * Math.min(2, lineCount))
          visible: card.hasBody
          opacity: card.contentOpacity

          textFormat: Text.StyledText
          text: card.redacted ? I18n.t("notifications.redactedBody") : String(card.row.bodyRich || "")
          color: card.bodyColor
          // Vista: blue links, Segoe UI 9 pt black body.
          linkColor: "#0000FF"
          font.family: "Segoe UI"
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          maximumLineCount: card.bodyLines
          elide: Text.ElideRight
          // Second gate: Markup already drops anchors it will not vouch for.
          onLinkActivated: function(url) { card.linkOpened(); Security.openExternalUrl(url) }
        }
      }
    }

    // The buttons, as a bar along the card's bottom edge: a hairline above,
    // equal segments split by hairlines, three to a line, and a short last line
    // stretched across. Drawn in the card because the surface is clipped. In
    // an open deck only the card under the pointer, or the keyboard, has them;
    // otherwise the front card of each deck does.
    Item {
      id: deedArea
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                leftMargin: plate.borderLeft; rightMargin: plate.borderRight
                bottomMargin: plate.borderBottom }

      readonly property bool shown: card.allDeeds.length > 0 && (card.expanded ? card.hovered : card.place.front)
      readonly property int columns: Math.max(1, Math.min(3, card.allDeeds.length))
      readonly property int rows: Math.ceil(card.allDeeds.length / columns)
      readonly property real rule: 1
      readonly property color ruleColor: Qt.rgba(card.dimColor.r, card.dimColor.g, card.dimColor.b, 0.35)
      readonly property real segmentHeight: Style.spacing.controlHeight + Style.space(6)
      readonly property real barHeight: rows * (rule + segmentHeight)
      // What the state asks for; the drawn height is whatever slack the
      // scene has given the card so far.
      readonly property real wanted: shown ? barHeight : 0
      height: Math.max(0, card.drawnHeight - card.fixedHeight)
      visible: height > 0
      clip: true

      Item {
        id: deedRow
        anchors.bottom: parent.bottom
        width: parent.width
        height: deedArea.barHeight
        opacity: deedArea.shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: card.fade; easing.type: Easing.InOutQuad } }

        Repeater {
          model: card.allDeeds
          DeedButton {
            required property var modelData
            required property int index
            readonly property int line: Math.floor(index / deedArea.columns)
            readonly property int slot: index % deedArea.columns
            readonly property int perLine: line < deedArea.rows - 1 ? deedArea.columns
                                           : card.allDeeds.length - line * deedArea.columns
            // Where the segment starts in reading order; the first action
            // sits on the right in a right-to-left language.
            readonly property real start: Math.round(slot * deedRow.width / perLine)
            deed: modelData
            toast: card
            hint: card.selected && index < 9 ? String(index + 1) : ""
            rule: deedArea.rule
            ruleColor: deedArea.ruleColor
            leftRule: slot > 0
            width: Math.round((slot + 1) * deedRow.width / perLine) - start
            x: card.LayoutMirroring.enabled ? deedRow.width - start - width : start
            y: line * (deedArea.rule + deedArea.segmentHeight)
            height: deedArea.rule + deedArea.segmentHeight
          }
        }
      }
    }

    // Under the content (z: -1) so buttons get their clicks first; anything
    // that does not accept a click falls through to here.
    MouseArea {
      anchors.fill: parent
      z: -1
      // Not hoverEnabled: a card taking hover would starve the deck's region.
      hoverEnabled: false
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      onClicked: function(mouse) {
        if (mouse.button === Qt.LeftButton) card.activated()
        else card.dismissed()
      }
    }
  }
}
