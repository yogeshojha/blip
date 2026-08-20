import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "yogeshojha.blip"
  ipcTarget: "blip-panel"

  readonly property var blip: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool armed: blip ? blip.armed : false
  readonly property bool suppressed: blip ? blip.suppressed : false
  readonly property bool visibleIndicator: blip ? blip.showIndicator : true
  readonly property var modules: blip ? blip.modules : []

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string statusText: {
    if (!blip) return "Not running"
    if (!armed) return "Disarmed"
    if (suppressed) return "Paused while sharing"
    if (!blip.automatic) return "Keybind only"
    return "Watching selections"
  }

  readonly property string actionsPill: {
    if (!blip) return ""
    var total = blip.catalog.length
    var active = blip.activeCatalog.length
    return active === total ? total + " actions" : active + " of " + total
  }

  visible: visibleIndicator
  implicitWidth: visibleIndicator ? button.implicitWidth : 0
  implicitHeight: visibleIndicator ? button.implicitHeight : 0

  readonly property var quickToggles: [
    { key: "trigger", label: "Show automatically", description: "Show the bar as soon as you select something" },
    { key: "grabKeyboard", label: "Take the keyboard", description: "Arrows and letters work the moment it appears" },
    { key: "position", label: "Centre on screen", description: "Instead of just above the pointer" },
    { key: "allowNetwork", label: "Allow network actions", description: "Still asks before the first send, once per action" },
    { key: "pauseWhenSharing", label: "Pause while sharing", description: "No bar over a screen share or a recording" }
  ]

  readonly property var sliderSpecs: ({
    dwellSeconds: { label: "Fade after", min: 1, max: 30, step: 1, unit: "s" },
    maxActions: { label: "Actions on the bar", min: 3, max: 12, step: 1, unit: "" },
    minLength: { label: "Shortest selection", min: 1, max: 30, step: 1, unit: " chars" },
    debounceMs: { label: "Settle time", min: 0, max: 1000, step: 25, unit: "ms" }
  })

  readonly property var sliderOrder: ["dwellSeconds", "maxActions", "minLength", "debounceMs"]

  readonly property var navRows: {
    var rows = [{ kind: "hero", id: "hero" }]
    for (var i = 0; i < quickToggles.length; i++)
      rows.push({ kind: "toggle", id: quickToggles[i].key, spec: quickToggles[i] })
    for (var s = 0; s < sliderOrder.length; s++)
      rows.push({ kind: "slider", id: sliderOrder[s] })
    for (var m = 0; m < modules.length; m++) {
      rows.push({ kind: "module", id: modules[m].key, module: modules[m] })
      for (var a = 0; a < modules[m].actions.length; a++)
        rows.push({ kind: "action", id: modules[m].actions[a].id, action: modules[m].actions[a] })
    }
    rows.push({ kind: "button", id: "reload" })
    rows.push({ kind: "button", id: "folder" })
    rows.push({ kind: "button", id: "forget" })
    return rows
  }

  property int cursor: 0
  property bool cursorActive: false

  readonly property var cursorRow: cursorActive && cursor >= 0 && cursor < navRows.length ? navRows[cursor] : null
  readonly property string cursorId: cursorRow ? String(cursorRow.kind) + ":" + String(cursorRow.id) : ""

  function setCursorTo(kind, id) {
    cursorActive = true
    var key = kind + ":" + id
    for (var i = 0; i < navRows.length; i++) {
      if (String(navRows[i].kind) + ":" + String(navRows[i].id) === key) { cursor = i; return }
    }
  }

  function moveCursor(dy) {
    if (!navRows.length) return
    cursorActive = true
    cursor = Math.max(0, Math.min(navRows.length - 1, cursor + dy))
  }

  function activateCursor() {
    var row = cursorRow
    if (!row || !blip) return
    if (row.kind === "hero") blip.toggleArmed()
    else if (row.kind === "toggle") flipToggle(row.id)
    else if (row.kind === "module") toggleModule(row.module)
    else if (row.kind === "action") blip.setActionEnabled(row.id, !blip.isActionEnabled(row.id))
    else if (row.kind === "button" && row.id === "reload") blip.rescan()
    else if (row.kind === "button" && row.id === "folder") blip.openActionsDir()
    else if (row.kind === "button" && row.id === "forget") blip.forgetConsent()
  }

  function adjustCursor(dx) {
    var row = cursorRow
    if (!row || !blip || row.kind !== "slider") return
    var spec = sliderSpecs[row.id]
    var value = sliderValue(row.id)
    blip.persist(row.id, Math.max(spec.min, Math.min(spec.max, value + dx * spec.step)))
  }

  function toggleValue(key) {
    if (!blip) return false
    if (key === "trigger") return blip.automatic
    if (key === "grabKeyboard") return blip.grabKeyboard
    if (key === "position") return blip.centred
    if (key === "allowNetwork") return blip.allowNetwork
    if (key === "pauseWhenSharing") return blip.pauseWhenSharing
    return false
  }

  function flipToggle(key) {
    if (!blip) return
    if (key === "trigger") blip.persist("trigger", blip.automatic ? "Keybind only" : "Automatic")
    else if (key === "position") blip.persist("position", blip.centred ? "At the cursor" : "Screen centre")
    else if (key === "grabKeyboard") blip.persist("grabKeyboard", !blip.grabKeyboard)
    else if (key === "allowNetwork") blip.persist("allowNetwork", !blip.allowNetwork)
    else if (key === "pauseWhenSharing") blip.persist("pauseWhenSharing", !blip.pauseWhenSharing)
  }

  function sliderValue(key) {
    if (!blip) return 0
    if (key === "dwellSeconds") return Math.round(blip.dwellMs / 1000)
    if (key === "maxActions") return blip.maxActions
    if (key === "minLength") return blip.minLength
    if (key === "debounceMs") return blip.debounceMs
    return 0
  }

  function moduleEnabledCount(module) {
    if (!blip || !module) return 0
    var n = 0
    for (var i = 0; i < module.actions.length; i++) {
      if (blip.isActionEnabled(module.actions[i].id)) n++
    }
    return n
  }

  function toggleModule(module) {
    if (!blip || !module) return
    var ids = []
    for (var i = 0; i < module.actions.length; i++) ids.push(module.actions[i].id)
    blip.setActionsEnabled(ids, moduleEnabledCount(module) < module.actions.length)
  }

  function scrollItemIntoView(item) {
    if (!flick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(flick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = flick.contentY
      var viewBottom = viewTop + flick.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) flick.contentY = Math.min(maxY, bottom + margin - flick.height)
    })
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursor = 0
    if (flick) flick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    text: "󰗧"
    active: root.armed && !root.suppressed
    dimmed: !root.armed || root.suppressed
    tooltipText: {
      if (!root.blip) return "Blip"
      if (!root.armed) return "Blip is disarmed · click for controls"
      if (root.suppressed) return "Blip is paused while the screen is shared"
      return "Blip is watching selections · click for controls"
    }

    onPressed: function(mouseButton) {
      if (!root.blip) return
      if (mouseButton === Qt.RightButton) root.blip.toggleArmed()
      else if (mouseButton === Qt.MiddleButton) root.blip.present(root.blip.selection, true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.adjustCursor(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") { if (root.blip) root.blip.rescan() }
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          Item {
            id: heroBlock
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.cursorId === "hero:hero"
            function focusHero() { root.setCursorTo("hero", "hero") }

            PanelHero {
              id: hero
              width: parent.width
              title: "Blip"
              meta: root.statusText
              detail: root.actionsPill
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.armed && !root.suppressed ? 1.0 : 0.5

              iconComponent: Component {
                Text {
                  text: "󰗧"
                  color: root.armed && !root.suppressed ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: armedSwitch
                  checked: root.armed
                  hasCursor: heroBlock.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) heroBlock.focusHero() }
                  onToggled: if (root.blip) root.blip.toggleArmed()

                  PanelToolTip {
                    visible: armedSwitch.containsMouse
                    text: root.armed ? "Disarm Blip" : "Arm Blip"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: root.blip !== null && root.blip.catalogErrors.length > 0
            width: parent.width
            text: root.blip && root.blip.catalogErrors.length > 0
              ? String(root.blip.catalogErrors[0]) : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "BEHAVIOUR"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.quickToggles

              SettingToggleRow {
                width: parent.width
                spec: modelData
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "TUNING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            SettingSliderRow { width: parent.width; settingKey: "dwellSeconds" }
            SettingSliderRow { width: parent.width; settingKey: "maxActions"; ticks: 10 }
            SettingSliderRow { width: parent.width; settingKey: "minLength" }
            SettingSliderRow { width: parent.width; settingKey: "debounceMs" }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "MODULES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.modules

            Column {
              width: column.width
              spacing: Style.space(2)

              readonly property var module: modelData

              ModuleHeaderRow {
                width: parent.width
                module: parent.module
              }

              Repeater {
                model: parent.module.actions

                ActionToggleRow {
                  width: column.width
                  action: modelData
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.space(8)

            FooterButton {
              buttonId: "reload"
              text: "Reload"
              iconText: "󰑐"
              tooltipText: "Rescan action files now"
              onClicked: if (root.blip) root.blip.rescan()
            }

            FooterButton {
              buttonId: "folder"
              text: "Edit actions"
              iconText: "󰝒"
              tooltipText: "Open your actions folder"
              onClicked: if (root.blip) root.blip.openActionsDir()
            }

            FooterButton {
              buttonId: "forget"
              text: "Consents"
              iconText: "󰃢"
              tooltipText: "Ask again before any network action sends"
              onClicked: if (root.blip) root.blip.forgetConsent()
            }
          }

          Text {
            width: parent.width
            text: "↑↓ move · Enter toggle · Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component SettingToggleRow: CursorSurface {
    id: toggleRow

    property var spec: null
    readonly property string settingKey: spec ? String(spec.key) : ""
    readonly property bool value: root.toggleValue(settingKey)

    hasCursor: root.cursorId === "toggle:" + settingKey
    foreground: root.foreground
    implicitHeight: toggleContent.implicitHeight + Style.space(12)

    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(toggleRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursorTo("toggle", toggleRow.settingKey)
      onClicked: root.flipToggle(toggleRow.settingKey)
    }

    Row {
      id: toggleContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Column {
        width: parent.width - toggleTrack.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: toggleRow.spec ? toggleRow.spec.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: toggleRow.spec ? toggleRow.spec.description : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        id: toggleTrack
        anchors.verticalCenter: parent.verticalCenter
        checked: toggleRow.value
        interactive: false
        cursorRing: false
        trackHeight: Style.space(18)
        foreground: root.foreground
      }
    }
  }

  component SettingSliderRow: CursorSurface {
    id: sliderRow

    property string settingKey: ""
    property int ticks: 0
    readonly property var spec: root.sliderSpecs[settingKey]
    readonly property int value: root.sliderValue(settingKey)

    hasCursor: root.cursorId === "slider:" + settingKey
    foreground: root.foreground
    implicitHeight: sliderContent.implicitHeight + Style.space(12)

    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(sliderRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.setCursorTo("slider", sliderRow.settingKey)
    }

    Column {
      id: sliderContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(4)

      Row {
        width: parent.width

        Text {
          text: sliderRow.spec ? sliderRow.spec.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Item { width: parent.width - parent.children[0].implicitWidth - valueText.implicitWidth; height: 1 }

        Text {
          id: valueText
          text: (slider.dragging ? Math.round(slider.liveValue) : sliderRow.value)
            + (sliderRow.spec ? sliderRow.spec.unit : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSlider {
        id: slider
        width: parent.width
        bar: root.bar
        minimum: sliderRow.spec ? sliderRow.spec.min : 0
        maximum: sliderRow.spec ? sliderRow.spec.max : 1
        value: sliderRow.value
        step: sliderRow.spec ? sliderRow.spec.step : 1
        integer: true
        tickCount: sliderRow.ticks
        onReleased: function(next) {
          if (root.blip) root.blip.persist(sliderRow.settingKey, Math.round(next))
        }
      }
    }
  }

  component ModuleHeaderRow: CursorSurface {
    id: moduleRow

    property var module: null
    readonly property int total: module ? module.actions.length : 0
    readonly property int enabledCount: {
      if (!root.blip || !module) return 0
      var disabled = root.blip.disabledSet
      var n = 0
      for (var i = 0; i < module.actions.length; i++) {
        if (disabled[module.actions[i].id] !== true) n++
      }
      return n
    }

    hasCursor: root.cursorId === "module:" + (module ? module.key : "")
    foreground: root.foreground
    implicitHeight: moduleContent.implicitHeight + Style.space(12)

    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(moduleRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursorTo("module", moduleRow.module ? moduleRow.module.key : "")
      onClicked: root.toggleModule(moduleRow.module)
    }

    Row {
      id: moduleContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Column {
        width: parent.width - moduleTrack.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: moduleRow.module ? moduleRow.module.title : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: moduleRow.enabledCount === moduleRow.total
            ? moduleRow.total + (moduleRow.total === 1 ? " action" : " actions")
            : moduleRow.enabledCount + " of " + moduleRow.total + " on"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      ToggleSwitch {
        id: moduleTrack
        anchors.verticalCenter: parent.verticalCenter
        checked: moduleRow.enabledCount === moduleRow.total && moduleRow.total > 0
        interactive: false
        cursorRing: false
        trackHeight: Style.space(18)
        foreground: root.foreground
      }
    }
  }

  component ActionToggleRow: CursorSurface {
    id: actionRow

    property var action: null
    readonly property string actionId: action ? String(action.id) : ""
    readonly property bool enabledValue: !root.blip || root.blip.disabledSet[actionId] !== true

    hasCursor: root.cursorId === "action:" + actionId
    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.space(10)

    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(actionRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursorTo("action", actionRow.actionId)
      onClicked: if (root.blip) root.blip.setActionEnabled(actionRow.actionId, !actionRow.enabledValue)
    }

    Row {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(18)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.icon
        horizontalAlignment: Text.AlignHCenter
        text: actionRow.action ? String(actionRow.action.icon || "") : ""
        color: actionRow.enabledValue ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        opacity: actionRow.enabledValue ? 1.0 : 0.6
      }

      Column {
        width: parent.width - Style.font.icon - actionTrack.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          width: parent.width
          text: actionRow.action ? String(actionRow.action.label || "") : ""
          color: actionRow.enabledValue ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          visible: text !== ""
          width: parent.width
          text: actionRow.action ? String(actionRow.action.description || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        id: actionTrack
        anchors.verticalCenter: parent.verticalCenter
        checked: actionRow.enabledValue
        interactive: false
        cursorRing: false
        trackHeight: Style.space(16)
        foreground: root.foreground
      }
    }
  }

  component FooterButton: Button {
    id: footerButton

    property string buttonId: ""

    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    hasCursor: root.cursorId === "button:" + buttonId

    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(footerButton)
    onHovered: function(on) { if (on) root.setCursorTo("button", buttonId) }
  }
}
