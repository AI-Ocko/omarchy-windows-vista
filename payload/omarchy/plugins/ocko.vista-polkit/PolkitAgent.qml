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

  // ======================================================== Vista Run As dialog
  // ocko.vista-polkit: everything above this line is omarchy.polkit 4.0.6
  // unchanged (flow handling, PAM/fingerprint logic, cancel/submit). Only the
  // window is Vista's "Run As" credential dialog, built from the shared chrome in
  // omarchy/vista/qml. Security is the stock dialog's: a full-screen Overlay
  // surface with exclusive keyboard focus, the request's exact message (not
  // the shortened authorizationLabel), the action id, the identity being
  // authenticated, any PAM info/error text, and a masked password field unless
  // PAM asks for a visible response.
  readonly property var flowIdentities: polkitAgent.flow && polkitAgent.flow.identities ? polkitAgent.flow.identities : []
  readonly property string actionId: polkitAgent.flow ? String(polkitAgent.flow.actionId || "") : ""
  readonly property bool supplementaryIsError: polkitAgent.flow ? !!polkitAgent.flow.supplementaryIsError : false

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

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.refocus()
    }

    VistaWindow {
      id: card
      width: panel.s(372)
      height: card.captionHeight + body.implicitHeight + panel.s(12 + 12) + card.frameWidth
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.shakeOffset
      title: "Run As"
      buttons: ["close"]
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

      Column {
        id: body
        x: panel.s(12)
        y: panel.s(12)
        width: card.client.width - panel.s(24)
        spacing: panel.s(8)

        Row {
          spacing: panel.s(12)
          Image {
            width: panel.s(32)
            height: panel.s(32)
            source: VistaScheme.icon(194, 32)
            smooth: true
          }
          Column {
            width: body.width - panel.s(44)
            spacing: panel.s(4)
            // The request, verbatim, as the authority sent it.
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.currentMessage
              wrapMode: Text.Wrap
              color: "#000000"
              font.family: "Segoe UI"
              font.bold: true
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              visible: root.actionId !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: "Action: " + root.actionId
              wrapMode: Text.WrapAnywhere
              color: "#404040"
              font.family: "Segoe UI"
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        VistaGroupBox {
          id: who
          width: body.width
          height: whoCol.implicitHeight + panel.s(24) + panel.s(6)
          caption: "Authenticate as"

          Column {
            id: whoCol
            width: parent.width
            spacing: panel.s(6)

            // One radio per identity polkit offers; choosing one restarts the
            // conversation for that identity (AuthFlow.selectedIdentity).
            Repeater {
              model: root.flowIdentities.length
              Row {
                required property int index
                readonly property var identity: root.flowIdentities[index]
                readonly property bool chosen: !!polkitAgent.flow && polkitAgent.flow.selectedIdentity === identity
                spacing: panel.s(6)
                Image {
                  width: panel.s(13)
                  height: panel.s(13)
                  anchors.verticalCenter: parent.verticalCenter
                  source: VistaScheme.art("radio-" + (parent.chosen ? 4 : 0))
                }
                Text {
                  text: root.identityLabel(parent.identity)
                  textFormat: Text.PlainText
                  color: "#000000"
                  font.family: "Segoe UI"
                  font.pixelSize: Style.font.bodySmall
                  MouseArea { anchors.fill: parent; onClicked: root.selectIdentity(parent.parent.identity) }
                }
              }
            }

            Row {
              spacing: panel.s(8)
              Text {
                width: panel.s(70)
                anchors.verticalCenter: parent.verticalCenter
                text: root.fingerprintMode ? "Fingerprint:" : (root.currentPrompt ? root.currentPrompt.replace(/\s*:?\s*$/, ":") : "Password:")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: "#000000"
                font.family: "Segoe UI"
                font.pixelSize: Style.font.bodySmall
              }
              Item {
                width: whoCol.width - panel.s(78)
                height: panel.s(21)
                Text {
                  visible: root.fingerprintMode
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Touch the fingerprint reader."
                  color: "#000000"
                  font.family: "Segoe UI"
                  font.pixelSize: Style.font.bodySmall
                }
                VistaTextField {
                  id: passwordField
                  visible: !root.fingerprintMode
                  anchors.fill: parent
                  readOnly: root.submitted || root.errorFlash
                  placeholder: root.submitted ? "Checking..." : ""
                  echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
                }
              }
            }
          }
        }

        // PAM's own info or error line, then Vista's logon-failure text.
        Text {
          visible: text !== ""
          width: body.width
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: root.errorFlash ? "Logon failure: unknown user name or bad password." : root.currentSupplementary
          color: root.errorFlash || root.supplementaryIsError ? Commons.Color.polkit.textError : "#000000"
          font.family: "Segoe UI"
          font.pixelSize: Style.font.bodySmall
        }

        Item {
          width: body.width
          height: panel.s(23)
          Row {
            anchors.right: parent.right
            spacing: panel.s(6)
            VistaButton {
              text: "OK"
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
      }
    }
  }

  // The stock flow code above addresses the field as passwordInput.
  readonly property var passwordInput: passwordField.input
}
