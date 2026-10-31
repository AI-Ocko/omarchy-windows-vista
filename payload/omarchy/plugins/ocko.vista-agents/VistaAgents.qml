import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import "../../vista/qml"

// The agents dashboard as an Vista property sheet, over the stock agents
// panel's model. `host` is the panel (ocko.vista-agents Panel.qml) or, for the
// screenshot harness, a mock with the same members; `usage` is its Main.
//
// host reads:  providers, providerIndex, provider, limits, models, balance,
//   balanceAlarming, cursorActive
// host calls: selectProvider, refreshNow, launchAgent, close, heroMeta,
//   resetMsFor, formatDuration, formatMoney, balanceDetailText, dayLabel,
//   dayTooltip, weekPeak, todayDate, modelTooltip, footerText,
//   iconCandidatesForProvider
// usage calls: formatTokenCount
Item {
  id: view

  required property var host
  property var usage: null
  property real maxHeight: 0
  // Stock's handlers set panelFlick.contentY; this is that Flickable's.
  property alias contentY: flick.contentY

  readonly property var p: host.provider
  readonly property var days: p ? (p.recentDays || []) : []
  readonly property real dayPeak: Math.max(1, host.weekPeak(p))
  readonly property real balanceRatio: host.balance && host.balance.funded > 0
    ? Math.max(0, Math.min(1, host.balance.remaining / host.balance.funded)) : -1
  // Vista draws a warning in red text; the progress chunks have no alarm colour.
  readonly property color alarmText: "#FF0000"

  function s(n) { return Style.space(n) }
  function du(x) { return Style.space(Math.round(x * 1.5)) }
  function dv(y) { return Style.space(Math.round(y * 13 / 8)) }
  function tokens(n) { return view.usage ? view.usage.formatTokenCount(Number(n || 0)) : String(n || 0) }
  // An VistaGroupBox's height around a column: caption, gap, content, inset.
  function boxHeight(c) { return fm.height + s(6) + c.implicitHeight + s(9) }

  function scrollBy(dy) {
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + dy))
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
      elide: Text.ElideRight
    }
  }

  // The stock mark, walking its candidates; the Microsoft Agent icon (the
  // tray art) when the provider ships none.
  component Mark: Item {
    id: mark
    // sc.face is a string in VistaScheme's table; stock's luminance test reads
    // .r/.g/.b, so hand it a color.
    readonly property var allCandidates: view.p ? view.host.iconCandidatesForProvider(view.p, Qt.color(VistaScheme.sc.face)) : []
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
      sourceSize.width: view.s(32) * 2
      sourceSize.height: view.s(32) * 2
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
    titles: view.host.providers.length > 0
      ? view.host.providers.map(function(q) { return q.providerName }) : ["Agents"]
    tab: view.host.providerIndex
    onTabClicked: function(i) {
      view.host.cursorActive = true
      view.host.selectProvider(i)
    }
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

          VistaLabel {
            visible: view.host.providers.length === 0
            width: col.width
            topPadding: view.dv(20)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---- status: stock's warning card as an Vista warning line ----
          Row {
            visible: !!view.p && String(view.p.usageStatusText || "") !== ""
            width: col.width
            spacing: view.du(7)
            Image {
              width: view.s(32)
              height: view.s(32)
              source: VistaScheme.sysIcon("warning", 32)
              smooth: true
            }
            VistaLabel {
              width: col.width - view.s(32) - view.du(7)
              anchors.verticalCenter: parent.verticalCenter
              text: view.p ? String(view.p.authHelpText || "") : ""
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
            }
          }

          // ---- balance ----
          VistaGroupBox {
            visible: !!view.host.balance
            width: col.width
            height: view.boxHeight(balanceCol)
            caption: "Balance"
            Column {
              id: balanceCol
              width: parent.width
              Meter {
                width: parent.width
                title: "Prepaid credits:"
                valueText: view.host.balance ? view.host.formatMoney(view.host.balance.remaining, view.host.balance.currency) : ""
                alarming: view.host.balanceAlarming
                value: view.balanceRatio
                note: view.host.balanceDetailText(view.host.balance)
              }
            }
          }

          // ---- limits ----
          VistaGroupBox {
            visible: view.host.limits.length > 0
            width: col.width
            height: view.boxHeight(limitsCol)
            caption: "Limits"
            Column {
              id: limitsCol
              width: parent.width
              spacing: view.dv(6)
              Repeater {
                model: view.host.limits
                Meter {
                  required property var modelData
                  width: limitsCol.width
                  title: modelData.title
                  valueText: modelData.percent >= 0 ? Math.round(modelData.percent * 100) + "%" : "—"
                  alarming: modelData.percent >= 0.9
                  value: modelData.percent
                  note: {
                    var ms = view.host.resetMsFor(modelData)
                    return ms > 0 ? "Resets in " + view.host.formatDuration(ms) : ""
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
            visible: view.host.models.length > 0
            text: "Tokens by model:"
            textFormat: Text.PlainText
          }
          VistaListView {
            id: modelList
            visible: view.host.models.length > 0
            width: col.width
            height: headerHeight + rowHeight * view.host.models.length + 2
            columns: [{ title: "Model", width: 190 }, { title: "Tokens", width: 80 }, { title: "Relative", width: 60 }]
            rows: view.host.models.map(function(r) {
              return [r.name, view.tokens(r.total), Math.round(100 * r.total / Math.max(1, view.host.models[0].total)) + "%"]
            })
            MouseArea {
              id: modelHover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.NoButton
              readonly property int row: containsMouse
                ? Math.floor((mouseY - modelList.headerHeight - 1) / modelList.rowHeight) : -1
              onRowChanged: {
                var r = view.host.models[row]
                if (row >= 0 && r) view.showTip(modelList, view.host.modelTooltip(r))
                else view.hideTip(modelList)
              }
            }
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
          text: view.host.footerText()
          textFormat: Text.PlainText
          elide: Text.ElideRight
        }
        Row {
          id: pushButtons
          anchors.right: parent.right
          spacing: view.s(6)
          VistaButton {
            width: view.s(100)
            text: "Launch Agent..."
            onClicked: view.host.launchAgent()
          }
          VistaButton {
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
