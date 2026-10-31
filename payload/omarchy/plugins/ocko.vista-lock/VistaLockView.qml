import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../../vista/qml"

// The Windows Vista logon screen, locked: the 190 rp zoomed user tile with
// the account picture, the user name and "Locked", the password box with
// its cue banner and the round arrow, Ease of Access bottom left, the
// Windows Vista wordmark centred and the red power button bottom right, and
// the Switch User button under the box.
// Layout and art are authui.dll's (UIFILE 11000, BITMAP 111xx; logon/ in
// omarchy/vista/assets/graphics, cut by vista-art). The power and Ease of
// Access buttons are drawn but inert: a locked session offers no actions
// without the password. Falls back to the stock LockView without the art.
Item {
  id: root

  // ---- the stock LockView interface (Service.qml binds these)
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function forcePasswordFocus() {
    if (vistaReady) passwordInput.forceActiveFocus()
    else if (stockLoader.item) stockLoader.item.forcePasswordFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (!vistaReady || passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  // Wrong password: OK takes the keys; dismissed, the box has them again.
  onErrorStateChanged: {
    if (!vistaReady) return
    if (errorState) Qt.callLater(function() { ok.forceActiveFocus() })
    else Qt.callLater(forcePasswordFocus)
  }
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // ---- Vista
  readonly property string home: Quickshell.env("HOME")
  readonly property string art: "file://" + home + "/.config/omarchy/vista/assets/graphics/logon/"
  readonly property string userLogin: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
  property string fullName: userLogin
  property string pictureUrl: art + "../account-pictures/usertile7.png"

  function rp(n) { return Style.space(n) }
  function pt(n) { return Style.space(n * 4 / 3) }
  function png(id) { return art + id + ".png" }

  readonly property bool errorState: failureMessage.length > 0

  // imageres IMAGE 5031-5043: the logon background closest to the screen's
  // aspect (the largest of equals), scaled to cover.
  readonly property var backgrounds: [[1280, 1024], [1280, 960], [1024, 768], [1600, 1200],
    [1440, 900], [1920, 1200], [1280, 768], [1360, 768], [1024, 1280], [960, 1280],
    [900, 1440], [768, 1280], [768, 1360]]
  readonly property string backgroundUrl: {
    var a = width / Math.max(1, height), best = backgrounds[0]
    for (var i = 1; i < backgrounds.length; i++) {
      var b = backgrounds[i], d = Math.abs(b[0] / b[1] - a), e = Math.abs(best[0] / best[1] - a)
      if (d < e - 0.001 || (Math.abs(d - e) <= 0.001 && b[0] > best[0])) best = b
    }
    return art + "bg-" + best[0] + "x" + best[1] + ".jpg"
  }

  // Loaded synchronously: the view must decide at once whether its art is
  // there, or the stock view flashes first.
  Image { id: probeTile; visible: false; asynchronous: false; source: root.png(11142) }
  Image { id: probeGo; visible: false; asynchronous: false; source: root.png(11153) }
  Image { id: probeBrand; visible: false; asynchronous: false; source: root.art + "brand.png" }
  readonly property bool vistaReady: probeTile.status === Image.Ready && probeGo.status === Image.Ready
    && probeBrand.status === Image.Ready

  // GECOS full name, as the Vista Start menu shows it.
  FileView {
    path: "/etc/passwd"
    blockLoading: true
    printErrors: false
    onLoaded: {
      var lines = String(text()).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split(":")
        if (f[0] !== root.userLogin) continue
        var gecos = String(f[4] || "").split(",")[0].trim()
        if (gecos) root.fullName = gecos
      }
    }
  }

  // The account picture the Vista Start menu uses (omarchy/vista/start-menu.json).
  FileView {
    path: root.home + "/.config/omarchy/vista/start-menu.json"
    blockLoading: true
    printErrors: false
    onLoaded: {
      try {
        var p = String(JSON.parse(text()).picture || "usertile7")
        root.pictureUrl = (p.charAt(0) === "/" ? "file://" + p
          : root.art + "../account-pictures/" + p + ".png")
      } catch (e) {}
    }
  }

  // ---- fallback: the stock view, only when the Vista art is missing
  Loader {
    id: stockLoader
    anchors.fill: parent
    active: !root.vistaReady
    sourceComponent: LockView {
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured
      authenticatingPassword: root.authenticatingPassword
      failureMessage: root.failureMessage
      failedAttempts: root.failedAttempts
      inputEnabled: root.inputEnabled
      loadBackground: root.loadBackground
      passwordText: root.passwordText
      onSubmitPassword: function(password) { root.submitPassword(password) }
      onPasswordTextEdited: function(password) { root.passwordTextEdited(password) }
      onClearFailureRequested: root.clearFailureRequested()
      onWakeRequested: root.wakeRequested()
    }
  }


  // ---- the logon screen
  Item {
    id: screen
    anchors.fill: parent
    visible: root.vistaReady

    Image {
      anchors.fill: parent
      source: root.backgroundUrl
      fillMode: Image.PreserveAspectCrop
      asynchronous: false
      smooth: true
    }

    MouseArea {
      anchors.fill: parent
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
    }

    // The selected user: tile, name, status, password box. Centred in the
    // space above the 96 rp options band.
    Column {
      id: account
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round((parent.height - band.height - height) / 2)
      spacing: 0
      visible: !root.errorState

      // PictureContainer 190 rp, Overlay = BITMAP 11142, Picture 126 rp
      // inside 32 rp of padding.
      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.rp(190); height: root.rp(190)
        Image {
          x: root.rp(32); y: root.rp(32)
          width: root.rp(126); height: root.rp(126)
          source: root.pictureUrl
          fillMode: Image.PreserveAspectCrop
          smooth: true
          mipmap: true
        }
        Image {
          anchors.fill: parent
          source: root.png(11142)
          smooth: true
        }
      }

      Item { width: 1; height: root.rp(4) }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.fullName
        color: "white"
        font.family: "Segoe UI"
        font.pixelSize: root.pt(18)
        style: Text.Raised
        styleColor: "#40000000"
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.authenticatingPassword ? "Welcome" : "Locked"
        color: "white"
        opacity: 0.85
        font.family: "Segoe UI"
        font.pixelSize: root.pt(9)
      }

      Item { width: 1; height: root.rp(12) }

      // FieldContainer: 34 rp ForceCenter, the field, Submit 30 rp + 4 rp.
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0
        Item { width: root.rp(34); height: root.rp(30) }

        Rectangle {
          id: field
          width: root.rp(225); height: root.rp(25)
          anchors.verticalCenter: parent.verticalCenter
          color: "white"
          border.width: 1
          border.color: passwordInput.activeFocus ? "#3d7bad" : "#8e8f8f"
          radius: root.rp(2)

          Text {
            anchors.fill: parent
            anchors.leftMargin: root.rp(5)
            verticalAlignment: Text.AlignVCenter
            visible: passwordInput.text.length === 0
            text: "Password"
            color: "#6d6d6d"
            font.family: "Segoe UI"
            font.italic: true
            font.pixelSize: root.pt(9)
          }

          TextInput {
            id: passwordInput
            anchors.fill: parent
            anchors.leftMargin: root.rp(5)
            anchors.rightMargin: root.rp(5)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            activeFocusOnPress: true
            enabled: root.vistaReady && root.inputEnabled && !root.authenticatingPassword
            readOnly: root.authenticatingPassword
            echoMode: TextInput.Password
            passwordCharacter: "●"
            passwordMaskDelay: 0
            color: "black"
            selectionColor: "#3399ff"
            selectedTextColor: "white"
            font.family: "Segoe UI"
            font.pixelSize: root.pt(9)
            cursorVisible: activeFocus && root.inputEnabled && !root.authenticatingPassword

            onTextChanged: {
              if (!root.syncingPasswordText) root.passwordTextEdited(text)
              if (text.length > 0) root.wakeRequested()
            }

            onAccepted: go.submit()

            Keys.onPressed: function(event) {
              root.wakeRequested()
              if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                root.passwordTextEdited("")
                event.accepted = true
              }
            }
          }
        }

        Item { width: root.rp(4); height: 1 }

        // Submit: BITMAP 11153 (normal), 11151 (hot), 11152 (pressed).
        Image {
          id: go
          width: root.rp(30); height: root.rp(30)
          anchors.verticalCenter: parent.verticalCenter
          source: root.png(goMouse.pressed ? 11152 : goMouse.containsMouse ? 11151 : 11153)
          smooth: true
          function submit() {
            var submitted = root.passwordText
            root.passwordTextEdited("")
            if (submitted.length > 0) root.submitPassword(submitted)
          }
          MouseArea {
            id: goMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.inputEnabled && !root.authenticatingPassword
            onClicked: { go.submit(); root.forcePasswordFocus() }
          }
        }
      }

      // Switch User (authui GenericButton, resstr 11413): drawn, inert; one
      // seat, no fast user switching.
      Item { width: 1; height: root.rp(24) }
      VistaButton {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.rp(100)
        text: "Switch User"
      }

      // Fingerprint hint under the box.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.fingerprintConfigured
        topPadding: root.rp(8)
        text: "You can also unlock with your fingerprint."
        color: "white"
        font.family: "Segoe UI"
        font.pixelSize: root.pt(9)
      }
    }

    // Wrong password: authui's message frame, error icon, text and OK.
    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round((parent.height - band.height - height) / 2)
      spacing: root.rp(30)
      visible: root.errorState

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.rp(8)
        Image {
          width: root.rp(16); height: root.rp(16)
          anchors.verticalCenter: parent.verticalCenter
          source: "file://" + root.home + "/.config/omarchy/vista/assets/graphics/user32/16/103.png"
        }
        Text {
          text: "The user name or password is incorrect."
          color: "white"
          font.family: "Segoe UI"
          font.pixelSize: root.pt(12)
        }
      }

      Rectangle {
        id: ok
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.rp(94); height: root.rp(28)
        radius: root.rp(3)
        border.color: okMouse.containsMouse ? "#3c7fb1" : "#707070"
        gradient: Gradient {
          GradientStop { position: 0.0; color: okMouse.containsMouse ? "#eaf6fd" : "#f2f2f2" }
          GradientStop { position: 0.49; color: okMouse.containsMouse ? "#d9f0fc" : "#ebebeb" }
          GradientStop { position: 0.5; color: okMouse.containsMouse ? "#bee6fd" : "#dddddd" }
          GradientStop { position: 1.0; color: okMouse.containsMouse ? "#a7d9f5" : "#cfcfcf" }
        }
        focus: root.errorState
        Keys.onReturnPressed: root.clearFailureRequested()
        Keys.onEnterPressed: root.clearFailureRequested()
        Keys.onSpacePressed: root.clearFailureRequested()
        Text {
          anchors.centerIn: parent
          text: "OK"
          font.family: "Segoe UI"
          font.pixelSize: root.pt(9)
          color: "black"
        }
        MouseArea {
          id: okMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: root.clearFailureRequested()
        }
      }
    }

    // Options band: 96 rp, 34 rp padding.
    Item {
      id: band
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: root.rp(96)

      // Ease of Access: 35x28 button (11123 normal, 11119 hot) round 11118.
      Image {
        x: root.rp(34)
        anchors.verticalCenter: parent.verticalCenter
        width: root.rp(35); height: root.rp(28)
        source: root.png(eoaMouse.containsMouse ? 11119 : 11123)
        Image { anchors.centerIn: parent; width: root.rp(24); height: root.rp(24); source: root.png(11118) }
        MouseArea { id: eoaMouse; anchors.fill: parent; hoverEnabled: true }
      }

      Image {
        anchors.centerIn: parent
        width: root.rp(350); height: root.rp(50)
        source: root.art + "brand.png"
        smooth: true
      }

      // Shut down (38x28: 11129 / hot 11127 / pressed 11128, glyph 11125)
      // and its options arrow (20x28: 11136 / 11134 / 11135, glyph 11132).
      Row {
        anchors.right: parent.right
        anchors.rightMargin: root.rp(34 + 6)
        anchors.verticalCenter: parent.verticalCenter
        Image {
          width: root.rp(38); height: root.rp(28)
          source: root.png(sdMouse.pressed ? 11128 : sdMouse.containsMouse ? 11127 : 11129)
          Image { anchors.centerIn: parent; source: root.png(11125); width: root.rp(sourceSize.width); height: root.rp(sourceSize.height) }
          MouseArea { id: sdMouse; anchors.fill: parent; hoverEnabled: true }
        }
        Image {
          width: root.rp(20); height: root.rp(28)
          source: root.png(soMouse.pressed ? 11135 : soMouse.containsMouse ? 11134 : 11136)
          Image { anchors.centerIn: parent; source: root.png(11132); width: root.rp(sourceSize.width); height: root.rp(sourceSize.height) }
          MouseArea { id: soMouse; anchors.fill: parent; hoverEnabled: true }
        }
      }
    }
  }
}
