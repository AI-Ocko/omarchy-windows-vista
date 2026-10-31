import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PolkitModel.js" as PolkitModel
import "../../vista/qml"

Item {
  id: root

  property string fontFamily: Style.font.menuFamily
  // Bound to the central [polkit] section in shell.toml via Commons.Color.qml.
  property color accent: Commons.Color.polkit.accent
  property color background: Commons.Color.polkit.background
  property color foreground: Commons.Color.polkit.text
  property color border: Commons.Color.polkit.border
  property color borderError: Commons.Color.polkit.borderError
  property var borderSpec: Border.surfaceSpec("polkit", errorFlash ? "border-error" : "border", errorFlash ? borderError : border, Math.max(1, Style.space(2)), "border-alpha")
  property color scrim: Commons.Color.polkit.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int fieldHeight: Math.max(Style.space(42), Style.spacing.controlHeight)

  property bool closing: false
  property bool submitted: false
  property string currentMessage: ""
  property string currentPrompt: ""
  property string currentSupplementary: ""
  property bool responseRequired: false
  property bool responseVisible: false
  property bool failed: false
  property bool errorFlash: false
  // pam_fprintd appears in the polkit PAM stack (a sensor is enrolled).
  property bool fingerprintConfigured: false
  // Lid shut right now — the reader is physically unreachable, so we fall back
  // to the password even when a sensor is enrolled. Refreshed per request.
  property bool laptopClosed: false
  property int shakeOffset: 0

  readonly property bool dialogVisible: polkitAgent.isActive || closing
  // We show one method at a time. Fingerprint owns the dialog while PAM is
  // waiting on the reader (lid open, sensor enrolled); the moment PAM asks for
  // a password — including immediately when the lid is shut and the clamshell
  // gate skips pam_fprintd — we switch to the password field instead.
  readonly property bool fingerprintMode: fingerprintConfigured && !laptopClosed && dialogVisible && !responseRequired && !submitted && !errorFlash
  readonly property int cardHeight: panel.height > 0 ? Math.min(fieldHeight + contentMargin * 2, panel.height - Style.gapsOut * 2) : fieldHeight + contentMargin * 2
  // Password mode is a wide field; fingerprint mode collapses to a square that
  // just frames the centered sensor icon.
  readonly property int cardWidth: fingerprintMode ? cardHeight : Math.min(Style.space(312), Math.max(Style.space(260), panel.width - Style.gapsOut * 2))

  function authorizationLabel(message) {
    return PolkitModel.authorizationLabel(message)
  }

  function loadPamConfig(raw) {
    fingerprintConfigured = PolkitModel.fingerprintConfiguredFromPamConfig(raw)
  }

  function refreshLidState() {
    if (!laptopClosedProc.running) laptopClosedProc.running = true
  }

  function resetSnapshot() {
    currentMessage = ""
    currentPrompt = ""
    currentSupplementary = ""
    responseRequired = false
    responseVisible = false
    failed = false
    errorFlash = false
    submitted = false
    passwordInput.text = ""
  }

  function syncFromFlow() {
    var flow = polkitAgent.flow
    if (!flow) return

    currentMessage = String(flow.message || "Authentication is needed...")
    currentPrompt = String(flow.inputPrompt || "")
    currentSupplementary = String(flow.supplementaryMessage || "")
    responseRequired = !!flow.isResponseRequired
    responseVisible = !!flow.responseVisible
    failed = !!flow.failed

    if (responseRequired) submitted = false
  }

  function beginFlow() {
    closeTimer.stop()
    closing = false
    submitted = false
    passwordInput.text = ""
    refreshLidState()
    syncFromFlow()
    Qt.callLater(refocus)
  }

  function refocus() {
    if (!dialogVisible) return
    // In fingerprint mode there is no field to type into — park focus on the
    // key catcher so Escape still cancels; otherwise focus the password field.
    if (fingerprintMode) keyCatcher.forceActiveFocus()
    else passwordInput.forceActiveFocus()
  }

  function submitResponse() {
    var flow = polkitAgent.flow
    if (!flow || !flow.isResponseRequired) return
    submitted = true
    errorFlash = false
    flow.submit(passwordInput.text)
    passwordInput.text = ""
    keyCatcher.forceActiveFocus()
  }

  function cancelRequest() {
    var flow = polkitAgent.flow
    passwordInput.text = ""
    submitted = false
    closing = true
    closeTimer.restart()
    if (flow) flow.cancelAuthenticationRequest()
  }

  function triggerFailureFeedback() {
    submitted = false
    errorFlash = true
    passwordInput.text = ""
    errorTimer.restart()
    shakeAnimation.restart()
    Qt.callLater(refocus)
  }

  Timer {
    id: closeTimer
    interval: 300
    repeat: false
    onTriggered: {
      closing = false
      resetSnapshot()
    }
  }

  Timer {
    id: errorTimer
    interval: 1200
    repeat: false
    onTriggered: root.errorFlash = false
  }

  SequentialAnimation {
    id: shakeAnimation
    NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
  }
  FileView {
    path: "/etc/pam.d/polkit-1"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadPamConfig(text())
    onLoadFailed: root.fingerprintConfigured = false
    onFileChanged: reload()
  }

  Process {
    id: laptopClosedProc
    command: ["bash", "-c", "omarchy-hw-laptop-closed && echo closed || echo open"]
    stdout: StdioCollector { id: laptopClosedOut; waitForEnd: true }
    onExited: root.laptopClosed = String(laptopClosedOut.text || "").trim() === "closed"
  }

  PolkitAgent {
    id: polkitAgent
    path: "/org/omarchy/PolkitAgent"

    onAuthenticationRequestStarted: root.beginFlow()
    onIsActiveChanged: {
      if (isActive) root.syncFromFlow()
      else if (!root.closing) root.resetSnapshot()
    }
    onIsRegisteredChanged: {
      if (isRegistered) console.log("omarchy polkit agent registered")
      else console.warn("omarchy polkit agent is not registered; another agent may be running")
    }
  }

  Connections {
    target: polkitAgent.flow

    function onIsResponseRequiredChanged() {
      root.syncFromFlow()
      if (!polkitAgent.flow || !polkitAgent.flow.isResponseRequired) passwordInput.text = ""
      Qt.callLater(root.refocus)
    }

    function onInputPromptChanged() { root.syncFromFlow() }
    function onResponseVisibleChanged() { root.syncFromFlow() }
    function onSupplementaryMessageChanged() { root.syncFromFlow() }
    function onFailedChanged() { root.syncFromFlow() }

    function onAuthenticationFailed() {
      root.syncFromFlow()
      root.triggerFailureFeedback()
    }

    function onAuthenticationSucceeded() {
      root.closing = true
      closeTimer.restart()
    }

    function onAuthenticationRequestCancelled() {
      root.closing = true
      closeTimer.restart()
    }
  }

  // ===================================================== Vista User Account Control
  // ocko.vista-polkit: everything above this line is omarchy.polkit 4.0.6
  // unchanged (flow handling, PAM/fingerprint logic, cancel/submit). Only the
  // window is Vista's UAC credential prompt (consent.exe, measured on
  // ms-uac-credential-rtm.jpg): the secure desktop (the screen dimmed), the
  // teal "Windows needs your permission to continue" banner, the program row,
  // one account tile per polkit identity with the password box in the chosen
  // one, Details, OK/Cancel and the UAC footer. Security is the stock dialog's:
  // a full-screen Overlay surface with exclusive keyboard focus, the request's
  // exact message, the action id, the identity being authenticated, any PAM
  // info/error text, and a masked password field unless PAM asks otherwise.
  readonly property var flowIdentities: polkitAgent.flow && polkitAgent.flow.identities ? polkitAgent.flow.identities : []
  readonly property string actionId: polkitAgent.flow ? String(polkitAgent.flow.actionId || "") : ""
  readonly property bool supplementaryIsError: polkitAgent.flow ? !!polkitAgent.flow.supplementaryIsError : false
  property bool detailsOpen: false
  readonly property string graphics: "file://" + Quickshell.env("HOME") + "/.config/omarchy/vista/assets/graphics/"

  function identityLabel(identity) {
    if (!identity) return ""
    var name = String(identity.displayName || identity.string || "")
    return identity.isGroup ? name + " (group)" : name
  }

  function selectIdentity(identity) {
    var flow = polkitAgent.flow
    if (!flow || !identity || flow.selectedIdentity === identity) return
    passwordInput.text = ""
    flow.selectedIdentity = identity
    Qt.callLater(root.refocus)
  }

  // The UAC sound, once per prompt (vista-sound gates it to Vista themes).
  Process { id: uacSound; command: [Quickshell.env("HOME") + "/.config/omarchy/vista/bin/vista-sound", "uac"] }
  onDialogVisibleChanged: {
    detailsOpen = false
    if (dialogVisible && !closing) uacSound.running = true
  }

  PanelWindow {
    id: panel
    visible: root.dialogVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    function s(n) { return Style.space(n) }

    // The secure desktop: Vista switched to a dimmed still of the desktop.
    Rectangle {
      anchors.fill: parent
      color: "#99000000"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.refocus()
    }

    VistaWindow {
      id: card
      width: panel.s(439)
      height: card.captionHeight + body.implicitHeight + card.frameWidth
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.shakeOffset
      title: "User Account Control"
      buttons: ["close"]
      face: "#FFFFFF"
      onCloseClicked: root.cancelRequest()

      MouseArea { anchors.fill: parent; onClicked: root.refocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.cancelRequest()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.responseRequired) root.submitResponse()
            event.accepted = true
          }
        }
      }

      component Label9: Text {
        textFormat: Text.PlainText
        color: "#000000"
        font.family: "Segoe UI"
        font.pixelSize: panel.s(12)
      }

      Column {
        id: body
        width: card.client.width
        spacing: 0

        // Banner: 40 px, the Windows-publisher teal, shield + headline.
        Rectangle {
          width: parent.width
          height: panel.s(40)
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#1B5674" }
            GradientStop { position: 0.1; color: "#05618A" }
            GradientStop { position: 1.0; color: "#0B5C84" }
          }
          Image {
            x: panel.s(10)
            anchors.verticalCenter: parent.verticalCenter
            width: panel.s(32); height: panel.s(32)
            source: root.graphics + "imageres/32/78.png"
            smooth: true
          }
          Text {
            x: panel.s(50)
            anchors.verticalCenter: parent.verticalCenter
            text: "Windows needs your permission to continue"
            color: "white"
            font.family: "Segoe UI"
            font.pixelSize: panel.s(16)
          }
        }

        Item { width: 1; height: panel.s(12) }
        Label9 { x: panel.s(20); text: "If you started this action, continue." }
        Item { width: 1; height: panel.s(8) }

        // The program row: what is asking (verbatim) and the action id.
        Row {
          x: panel.s(36)
          spacing: panel.s(30)
          Image {
            width: panel.s(32); height: panel.s(32)
            source: root.graphics + "consent/32/107.png"
            smooth: true
          }
          Column {
            width: body.width - panel.s(36 + 32 + 30 + 20)
            Label9 {
              width: parent.width
              text: root.currentMessage
              wrapMode: Text.Wrap
            }
            Label9 {
              visible: root.actionId !== ""
              width: parent.width
              text: root.actionId
              wrapMode: Text.WrapAnywhere
            }
          }
        }

        Item { width: 1; height: panel.s(10) }
        Label9 {
          x: panel.s(20)
          width: body.width - panel.s(40)
          wrapMode: Text.Wrap
          text: root.fingerprintMode ? "To continue, touch the fingerprint reader."
            : /^\s*password\s*:?\s*$/i.test(root.currentPrompt || "Password")
              ? "To continue, type an administrator password, and then click OK."
              : "To continue, type your " + root.currentPrompt.replace(/\s*:?\s*$/, "").toLowerCase() + ", and then click OK."
        }
        Item { width: 1; height: panel.s(12) }
        Rectangle { x: panel.s(12); width: body.width - panel.s(24); height: 1; color: "#DFDFDF" }
        Item { width: 1; height: panel.s(16) }

        // One tile per identity; the chosen one is highlighted and holds the
        // password box (one field: the stock flow addresses it as passwordInput).
        Item {
          id: tiles
          width: body.width
          height: tileCol.height
          readonly property int chosenIndex: {
            var f = polkitAgent.flow, ids = root.flowIdentities
            for (var i = 0; f && i < ids.length; i++) if (ids[i] === f.selectedIdentity) return i
            return 0
          }

          Column {
            id: tileCol
            width: parent.width
            Repeater {
              model: root.flowIdentities.length
              Item {
                id: tile
                required property int index
                readonly property var identity: root.flowIdentities[index]
                readonly property bool chosen: index === tiles.chosenIndex
                x: panel.s(26)
                width: body.width - panel.s(52)
                height: panel.s(70)

                Rectangle {
                  anchors.fill: parent
                  visible: tile.chosen || tileMouse.containsMouse
                  radius: panel.s(3)
                  border.color: "#BED1D7"
                  gradient: Gradient {
                    GradientStop { position: 0.0; color: "#EDFFFF" }
                    GradientStop { position: 1.0; color: "#DBF0F5" }
                  }
                }
                MouseArea {
                  id: tileMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.selectIdentity(tile.identity)
                }
                // The account picture in its 60 px frame.
                Rectangle {
                  x: panel.s(5); y: panel.s(5)
                  width: panel.s(60); height: panel.s(60)
                  radius: panel.s(3)
                  color: "white"
                  border.color: "#7A8692"
                  Image {
                    anchors.fill: parent
                    anchors.margins: panel.s(4)
                    source: root.graphics + "account-pictures/usertile7.png"
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                  }
                }
                Text {
                  x: panel.s(81)
                  y: tile.chosen && passwordField.visible ? panel.s(10) : (tile.height - height) / 2
                  text: root.identityLabel(tile.identity)
                  textFormat: Text.PlainText
                  color: "#000000"
                  font.family: "Segoe UI"
                  font.pixelSize: panel.s(16)
                }
              }
            }
          }

          VistaTextField {
            id: passwordField
            visible: !root.fingerprintMode && root.flowIdentities.length > 0
            x: panel.s(26 + 81)
            y: tiles.chosenIndex * panel.s(70) + panel.s(37)
            width: panel.s(193); height: panel.s(21)
            readOnly: root.submitted || root.errorFlash
            placeholder: root.submitted ? "Checking..." : (root.currentPrompt ? root.currentPrompt.replace(/\s*:?\s*$/, "") : "Password")
            echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
          }
        }

        // PAM's own info or error line, then Vista's logon-failure text.
        Item { width: 1; height: panel.s(8) }
        Label9 {
          visible: text !== ""
          x: panel.s(26)
          width: body.width - panel.s(52)
          wrapMode: Text.Wrap
          text: root.errorFlash ? "The user name or password is incorrect." : root.currentSupplementary
          color: root.errorFlash || root.supplementaryIsError ? "#CC0000" : "#000000"
        }

        // Details: the action id and identity in full.
        Column {
          visible: root.detailsOpen
          x: panel.s(26)
          width: body.width - panel.s(52)
          topPadding: panel.s(8)
          spacing: panel.s(2)
          Label9 { width: parent.width; wrapMode: Text.WrapAnywhere; text: "Action:  " + (root.actionId || "(none)") }
          Label9 {
            width: parent.width; wrapMode: Text.Wrap
            text: "Authenticating as:  " + root.identityLabel(polkitAgent.flow ? polkitAgent.flow.selectedIdentity : null)
          }
        }

        Item { width: 1; height: panel.s(20) }

        // Details expander and the buttons.
        Item {
          width: body.width
          height: panel.s(23)
          Row {
            x: panel.s(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.s(6)
            Rectangle {
              width: panel.s(19); height: panel.s(19)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              border.color: detMouse.containsMouse ? "#3C7FB1" : "#8E8F8F"
              gradient: Gradient {
                GradientStop { position: 0.0; color: "#FFFFFF" }
                GradientStop { position: 1.0; color: detMouse.containsMouse ? "#D9F0FC" : "#E6E6E6" }
              }
              Text {
                anchors.centerIn: parent
                text: root.detailsOpen ? "⌃" : "⌄"
                color: "#2B2B2B"
                font.pixelSize: panel.s(11)
                font.bold: true
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: (root.detailsOpen ? "Hide d" : "D") + "etails"
              color: "#000000"
              font.family: "Segoe UI"
              font.pixelSize: panel.s(12)
            }
          }
          MouseArea {
            id: detMouse
            width: panel.s(100); height: parent.height
            hoverEnabled: true
            onClicked: { root.detailsOpen = !root.detailsOpen; root.refocus() }
          }
          Row {
            anchors.right: parent.right
            anchors.rightMargin: panel.s(14)
            spacing: panel.s(8)
            VistaButton {
              text: root.fingerprintMode ? "Continue" : "OK"
              isDefault: true
              enabled: root.responseRequired && !root.submitted && !root.errorFlash
              onClicked: root.submitResponse()
            }
            VistaButton {
              text: "Cancel"
              onClicked: root.cancelRequest()
            }
          }
        }

        Item { width: 1; height: panel.s(12) }

        // Footer band.
        Rectangle {
          width: body.width
          height: panel.s(40)
          color: "#F0F0F0"
          Rectangle { width: parent.width; height: 1; color: "#DFDFDF" }
          Label9 {
            x: panel.s(14)
            anchors.verticalCenter: parent.verticalCenter
            text: "User Account Control helps stop unauthorized changes to your computer."
          }
        }
      }
    }
  }

  // The stock flow code above addresses the field as passwordInput.
  readonly property var passwordInput: passwordField.input
}
