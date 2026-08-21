import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "io.github.yogeshojha.blip"
  ipcTarget: "blip-panel"

  readonly property var blip: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool armed: blip ? blip.armed : false
  readonly property bool suppressed: blip ? blip.suppressed : false
  readonly property bool visibleIndicator: blip ? blip.showIndicator : true
  readonly property var modules: blip ? blip.modules : []
  readonly property var packs: blip ? blip.packList : []
  property string installNote: ""

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

  // The kit's hero pill is pushed to the trailing edge of the label column,
  // where it crowds the armed switch — the network panel dropped its own for
  // the same reason. The count rides in the meta line instead.
  readonly property string heroMeta: {
    var count = actionsPill
    return count === "" ? statusText : statusText + " · " + count
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
    { key: "pauseWhenSharing", label: "Pause while sharing", description: "No bar over a screen share or a recording" },
    { key: "allowNetwork", label: "Allow network actions", description: "Shows actions that send the selection, like Whois" }
  ]

  readonly property var sliderSpecs: ({
    dwellSeconds: { label: "Fade after", min: 1, max: 30, step: 1, unit: "s" },
    maxActions: { label: "Actions on the bar", min: 3, max: 12, step: 1, unit: "" },
    minLength: { label: "Shortest selection", min: 1, max: 30, step: 1, unit: " chars" },
    debounceMs: { label: "Settle time", min: 0, max: 1000, step: 25, unit: "ms" }
  })

  readonly property var sliderOrder: ["dwellSeconds", "maxActions", "minLength", "debounceMs"]

  // value doubles as the ButtonGroup option value and the tab key.
  readonly property var tabs: [
    { value: "general", label: "General" },
    { value: "actions", label: "Actions" },
    { value: "packs", label: "Packs" },
    { value: "tuning", label: "Tuning" }
  ]

  property int tab: 0
  readonly property string tabKey: String(tabs[tab].value)

  property var expandedModules: ({})
  property int chipCursor: 0
  // returnRequested precedes activateRequested only for Enter; that tells it from Space.
  property bool enterKey: false

  // Leaving the tab by mouse while the install field is focused would leave
  // the keyboard routed to a hidden editor.
  onTabKeyChanged: if (tabKey !== "packs" && installField.activeFocus) keyCatcher.forceActiveFocus()

  // Each tab is its own page: the cursor lands back on the strip and the
  // scroll starts at the top, so no row stays selected off-screen.
  function setTab(next) {
    var value = Math.max(0, Math.min(tabs.length - 1, next))
    if (value === tab) return
    var wasActive = cursorActive
    tab = value
    chipCursor = 0
    if (flick) flick.contentY = 0
    setCursorTo("tabs", "tabs")
    cursorActive = wasActive
  }

  function setTabByKey(key) {
    for (var i = 0; i < tabs.length; i++) {
      if (String(tabs[i].value) === String(key)) { setTab(i); return }
    }
  }

  readonly property var navRows: {
    var rows = [{ kind: "hero", id: "hero" }, { kind: "tabs", id: "tabs" }]
    if (tabKey === "general") {
      for (var i = 0; i < quickToggles.length; i++)
        rows.push({ kind: "toggle", id: quickToggles[i].key, spec: quickToggles[i] })
      if (blip && blip.consentCount > 0) rows.push({ kind: "consent", id: "consent" })
      rows.push({ kind: "choice", id: "searchEngine" })
      if (blip && blip.searchEngine === "Custom") rows.push({ kind: "searchurl", id: "searchurl" })
    } else if (tabKey === "actions") {
      for (var m = 0; m < modules.length; m++) {
        rows.push({ kind: "module", id: modules[m].key, module: modules[m] })
        if (expandedModules[modules[m].key] === true)
          rows.push({ kind: "chips", id: modules[m].key, module: modules[m] })
      }
    } else if (tabKey === "packs") {
      rows.push({ kind: "packinstall", id: "install" })
      for (var p = 0; p < packs.length; p++)
        rows.push({ kind: "pack", id: packs[p].name, pack: packs[p] })
    } else if (tabKey === "tuning") {
      for (var s = 0; s < sliderOrder.length; s++)
        rows.push({ kind: "slider", id: sliderOrder[s] })
    }
    return rows
  }

  property int cursor: 0
  property bool cursorActive: false

  readonly property var cursorRow: cursorActive && cursor >= 0 && cursor < navRows.length ? navRows[cursor] : null
  readonly property string cursorId: cursorRow ? String(cursorRow.kind) + ":" + String(cursorRow.id) : ""

  onCursorIdChanged: if (cursorRow && cursorRow.kind === "chips") chipCursor = 0

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

  function isModuleExpanded(key) {
    return expandedModules[String(key)] === true
  }

  function setModuleExpanded(key, on) {
    var next = {}
    for (var existing in expandedModules) next[existing] = expandedModules[existing]
    if (on) next[String(key)] = true
    else delete next[String(key)]
    expandedModules = next
    setCursorTo("module", key)
  }

  function activateCursor(viaEnter) {
    var row = cursorRow
    if (!row || !blip) return
    if (row.kind === "hero") blip.toggleArmed()
    // Enter on the strip steps into the tab rather than changing it.
    else if (row.kind === "tabs") moveCursor(1)
    else if (row.kind === "toggle") flipToggle(row.id)
    else if (row.kind === "consent") forgetConsents()
    else if (row.kind === "choice") searchDropdown.toggle()
    else if (row.kind === "searchurl") searchField.forceActiveFocus()
    else if (row.kind === "module") {
      if (viaEnter === false) toggleModule(row.module)
      else setModuleExpanded(row.id, !isModuleExpanded(row.id))
    }
    else if (row.kind === "chips") toggleChip(row.module)
    else if (row.kind === "packinstall") installField.forceActiveFocus()
    else if (row.kind === "pack") notePackResult(blip.packUpdate(row.id))
  }

  function forgetConsents() {
    if (!blip) return
    blip.forgetConsent()
    setCursorTo("toggle", "allowNetwork")
  }

  function toggleChip(module) {
    if (!blip || !module) return
    if (chipCursor < 0 || chipCursor >= module.actions.length) return
    var id = String(module.actions[chipCursor].id)
    blip.setActionEnabled(id, !blip.isActionEnabled(id))
  }

  // Refused operations (busy, bad url) surface here instead of vanishing.
  function notePackResult(result) {
    installNote = String(result).indexOf("error:") === 0 ? String(result).slice(7).replace(/^\s+/, "") : ""
    return installNote === ""
  }

  function submitPackInstall() {
    if (!blip) return
    if (!notePackResult(blip.packAdd(installField.text))) return
    installField.text = ""
    keyCatcher.forceActiveFocus()
  }

  function adjustCursor(dx) {
    var row = cursorRow
    if (!row || !blip) return
    if (row.kind === "tabs") { setTab(tab + dx); return }
    if (row.kind === "choice") { blip.cycleSearchEngine(dx); return }
    if (row.kind === "module") { setModuleExpanded(row.id, dx > 0); return }
    if (row.kind === "chips") {
      var count = row.module ? row.module.actions.length : 0
      if (count > 0) chipCursor = Math.max(0, Math.min(count - 1, chipCursor + dx))
      return
    }
    if (row.kind !== "slider") return
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

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursor = 0
      if (flick) flick.contentY = 0
      panelIntro.restart()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      // Collapse while hidden so reopening never shows the fold-up.
      expandedModules = ({})
      tab = 0
    }
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While an inline editor or the dropdown popup owns the keys, every
      // key belongs to it.
      blocked: installField.activeFocus || searchField.activeFocus || searchDropdown.popupOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.adjustCursor(dx)
      }
      onReturnRequested: root.enterKey = true
      onActivateRequested: {
        if (root.cursorActive) root.activateCursor(root.enterKey)
        root.enterKey = false
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onDeleteRequested: {
        var row = root.cursorRow
        if (row && row.kind === "pack" && root.blip) root.notePackResult(root.blip.packRemove(row.id))
      }
      onTextKey: function(t) {
        var digit = parseInt(t, 10)
        if (digit >= 1 && digit <= root.tabs.length) { root.setTab(digit - 1); return }
        if (t === "r" || t === "R") { if (root.blip) root.blip.rescan() }
        else if (t === "e") { if (root.blip) root.blip.openActionsDir() }
        else if (t === "g") {
          root.cursorActive = true
          root.cursor = 0
          flick.contentY = 0
        } else if (t === "G") {
          root.cursorActive = true
          root.cursor = root.navRows.length - 1
          flick.contentY = Math.max(0, flick.contentHeight - flick.height)
        }
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

        ParallelAnimation {
          id: panelIntro

          NumberAnimation {
            target: column
            property: "opacity"
            from: 0
            to: 1
            duration: 180
            easing.type: Easing.OutCubic
          }
          NumberAnimation {
            target: columnRise
            property: "y"
            from: Style.space(8)
            to: 0
            duration: 240
            easing.type: Easing.OutCubic
          }
        }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)
          transform: Translate { id: columnRise }

          Item {
            id: heroBlock
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.cursorId === "hero:hero"
            // Not a CursorSurface, so it needs its own scroll hook.
            onRingVisibleChanged: if (ringVisible) root.scrollItemIntoView(heroBlock)
            function focusHero() { root.setCursorTo("hero", "hero") }

            PanelHero {
              id: hero
              width: parent.width
              title: "Blip"
              meta: root.heroMeta
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

          // One nav row: the strip owns the cursor, and ←→ walks it.
          Item {
            id: tabStrip
            width: parent.width
            implicitHeight: tabGroup.implicitHeight

            readonly property bool ringVisible: root.cursorId === "tabs:tabs"
            onRingVisibleChanged: if (ringVisible) root.scrollItemIntoView(tabStrip)

            ButtonGroup {
              id: tabGroup
              anchors.horizontalCenter: parent.horizontalCenter
              options: root.tabs
              value: root.tabKey
              // The panel drives the cursor, so the group never takes Tab focus.
              focusable: false
              cursorIndex: tabStrip.ringVisible ? root.tab : -1
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onChanged: function(next) { root.setTabByKey(next) }
              onHovered: function(index, isHovered) { if (isHovered) root.setCursorTo("tabs", "tabs") }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            visible: root.tabKey === "general"
            spacing: Style.space(12)

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

              ConsentRow { width: parent.width }
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "SEARCH"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            CursorSurface {
              id: searchChoiceRow
              width: parent.width
              hasCursor: root.cursorId === "choice:searchEngine" && !searchDropdown.popupOpen
              foreground: root.foreground
              implicitHeight: searchChoiceContent.implicitHeight + Style.space(12)

              onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(searchChoiceRow)

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: root.setCursorTo("choice", "searchEngine")
              }

              Row {
                id: searchChoiceContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Column {
                  width: parent.width - searchDropdown.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: "Search with"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: "Where the Search action sends the selection"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Dropdown {
                  id: searchDropdown
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(140)
                  showLabel: false
                  options: {
                    var out = []
                    var engines = root.blip ? root.blip.searchEngines : []
                    for (var i = 0; i < engines.length; i++) out.push(engines[i].name)
                    return out
                  }
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(next) { if (root.blip) root.blip.persist("searchEngine", next) }
                  onHovered: function(on) { if (on) root.setCursorTo("choice", "searchEngine") }
                  onPopupOpenChanged: if (!popupOpen) keyCatcher.forceActiveFocus()
                }

                // The popup assigns value imperatively on select, which would
                // sever a plain binding to the service.
                Binding {
                  target: searchDropdown
                  property: "value"
                  value: root.blip ? root.blip.searchEngine : ""
                }
              }
            }

            CursorSurface {
              id: searchUrlRow

              readonly property bool custom: root.blip !== null && root.blip.searchEngine === "Custom"
              readonly property bool valid: root.blip ? root.blip.customSearchValid : false

              width: parent.width
              visible: custom
              hasCursor: root.cursorId === "searchurl:searchurl" && !searchField.activeFocus
              foreground: root.foreground
              implicitHeight: custom ? searchUrlContent.implicitHeight + Style.space(12) : 0

              onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(searchUrlRow)

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: root.setCursorTo("searchurl", "searchurl")
              }

              Column {
                id: searchUrlContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(4)

                TextField {
                  id: searchField
                  width: parent.width
                  placeholderText: "https://github.com/search?q=%s&type=code"
                  text: root.blip ? root.blip.customSearch : ""
                  foreground: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  onAccepted: if (root.blip) root.blip.persist("searchUrl", text)
                  Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                }

                Text {
                  width: parent.width
                  text: searchUrlRow.valid
                    ? "Enter to save."
                    : "Put %s where the selection goes, then press Enter. Until then, DuckDuckGo."
                  color: searchUrlRow.valid ? root.dim : root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.tabKey === "actions"
            spacing: Style.space(12)

            Item {
              width: parent.width
              implicitHeight: Math.max(actionsHeader.implicitHeight, actionsHeaderButtons.implicitHeight)

              PanelSectionHeader {
                id: actionsHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "ACTIONS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Row {
                id: actionsHeaderButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: "Rescan action files (r)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: if (root.blip) root.blip.rescan()
                }

                PanelActionButton {
                  iconText: "󰝒"
                  tooltipText: "Open your actions folder (e)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: if (root.blip) root.blip.openActionsDir()
                }
              }
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

                ModuleChipsArea {
                  width: parent.width
                  module: parent.module
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.tabKey === "packs"
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "PACKS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: packsColumn
              width: parent.width
              spacing: Style.space(6)

              CursorSurface {
                id: installRow
                width: parent.width
                hasCursor: root.cursorId === "packinstall:install" && !installField.activeFocus
                foreground: root.foreground
                implicitHeight: installContent.implicitHeight + Style.space(12)

                onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(installRow)

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.NoButton
                  onEntered: root.setCursorTo("packinstall", "install")
                }

                Row {
                  id: installContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  TextField {
                    id: installField
                    width: parent.width - installButton.implicitWidth - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "https://github.com/…/blip-pack-…"
                    foreground: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    enabled: !(root.blip && root.blip.packBusy)
                    onAccepted: root.submitPackInstall()
                    onTextChanged: root.installNote = ""
                    Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                  }

                  Button {
                    id: installButton
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Install"
                    iconText: "󰇚"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    enabled: installField.text.length > 0 && !(root.blip && root.blip.packBusy)
                    onClicked: root.submitPackInstall()
                  }
                }
              }

              Text {
                visible: text !== ""
                width: parent.width
                // A running operation outranks a stale validation note.
                text: root.blip && root.blip.packBusy ? root.blip.packStatus
                  : (root.installNote !== "" ? root.installNote : (root.blip ? root.blip.packStatus : ""))
                color: (root.blip && root.blip.packBusy) ? root.dim
                  : (root.installNote !== "" || (root.blip && root.blip.packStatusUrgent) ? root.urgent : root.dim)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              Text {
                visible: root.packs.length === 0
                width: parent.width
                text: "A pack is a git repo with actions/*.jsonc and scripts/."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Column {
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: root.packs

                  PackRow {
                    width: parent.width
                    pack: modelData
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            visible: root.tabKey === "tuning"
            spacing: Style.space(12)

            PanelSectionHeader {
              text: "FINE-TUNING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: slidersColumn
              width: parent.width
              spacing: Style.space(4)

              SettingSliderRow { width: parent.width; settingKey: "dwellSeconds" }
              SettingSliderRow { width: parent.width; settingKey: "maxActions"; ticks: 10 }
              SettingSliderRow { width: parent.width; settingKey: "minLength" }
              SettingSliderRow { width: parent.width; settingKey: "debounceMs" }
            }
          }

          Text {
            width: parent.width
            text: "1-4 tabs · ↑↓ move · ←→ change · Enter select · Esc close"
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

  component ConsentRow: CursorSurface {
    id: consentRow

    readonly property int count: root.blip ? root.blip.consentCount : 0

    visible: count > 0
    hasCursor: root.cursorId === "consent:consent"
    foreground: root.foreground
    implicitHeight: visible ? consentContent.implicitHeight + Style.space(12) : 0

    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(consentRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursorTo("consent", "consent")
      onClicked: root.forgetConsents()
    }

    Row {
      id: consentContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰃢"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width - parent.children[0].implicitWidth - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: consentRow.count + (consentRow.count === 1 ? " action" : " actions")
          + " allowed to send · forget"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
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
    readonly property string moduleKey: module ? String(module.key) : ""
    readonly property bool expanded: root.isModuleExpanded(moduleKey)
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

    hasCursor: root.cursorId === "module:" + moduleKey
    foreground: root.foreground
    implicitHeight: moduleContent.implicitHeight + Style.space(12)

    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(moduleRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursorTo("module", moduleRow.moduleKey)
      onClicked: root.setModuleExpanded(moduleRow.moduleKey, !moduleRow.expanded)
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
        width: parent.width - moduleTrack.width - moduleChevron.width - parent.spacing * 2
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
        cursorRing: false
        trackHeight: Style.space(18)
        foreground: root.foreground
        onToggled: root.toggleModule(moduleRow.module)

        PanelToolTip {
          visible: moduleTrack.containsMouse
          text: (moduleRow.enabledCount === moduleRow.total ? "Turn every action off" : "Turn every action on") + " (Space)"
          fontFamily: root.fontFamily
        }
      }

      Text {
        id: moduleChevron
        anchors.verticalCenter: parent.verticalCenter
        text: moduleRow.expanded ? "󰅀" : "󰅂"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  component ModuleChipsArea: Item {
    id: chipsArea

    property var module: null
    readonly property string moduleKey: module ? String(module.key) : ""
    readonly property bool shown: root.isModuleExpanded(moduleKey)
    readonly property bool isCursored: root.cursorId === "chips:" + moduleKey
    readonly property var cursorAction: isCursored && module
      && root.chipCursor >= 0 && root.chipCursor < module.actions.length
      ? module.actions[root.chipCursor] : null

    clip: true
    visible: implicitHeight > 0
    implicitHeight: shown ? chipsInner.implicitHeight + Style.space(6) : 0
    opacity: shown ? 1 : 0

    Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    onIsCursoredChanged: if (isCursored) root.scrollItemIntoView(chipsArea)

    Column {
      id: chipsInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: chipsArea.module ? chipsArea.module.actions : []

          PanelChip {
            action: modelData
            enabledValue: root.blip ? root.blip.isActionEnabled(String(modelData.id)) : true
            cursored: chipsArea.isCursored && index === root.chipCursor
            onHoveredChip: {
              root.setCursorTo("chips", chipsArea.moduleKey)
              root.chipCursor = index
            }
            onClicked: {
              root.setCursorTo("chips", chipsArea.moduleKey)
              root.chipCursor = index
              if (root.blip) root.blip.setActionEnabled(String(modelData.id),
                !root.blip.isActionEnabled(String(modelData.id)))
            }
          }
        }
      }

      // Fixed-height so the grid doesn't jump as descriptions come and go.
      Item {
        width: parent.width
        height: Style.font.caption + Style.space(4)

        Text {
          width: parent.width
          text: chipsArea.cursorAction
            ? String(chipsArea.cursorAction.description || chipsArea.cursorAction.label || "")
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component PanelChip: BorderSurface {
    id: chip

    property var action: null
    property bool enabledValue: true
    property bool cursored: false

    signal clicked()
    signal hoveredChip()

    readonly property string glyph: action ? String(action.icon || "") : ""
    readonly property string label: action ? String(action.label || "") : ""

    implicitWidth: chipBody.implicitWidth + Style.spacing.controlPaddingX * 2
    implicitHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.controlPaddingY * 2)
    radius: Style.cornerRadius
    color: cursored ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
    borderSpec: cursored
      ? Border.controlSpec("hover-cursor", root.foreground, Color.accent)
      : (enabledValue ? Border.controlSpec("normal", root.foreground, Color.accent) : Border.none())

    Behavior on color { ColorAnimation { duration: 80 } }

    Row {
      id: chipBody
      anchors.centerIn: parent
      spacing: Style.spacing.xs

      Text {
        visible: chip.glyph !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: chip.glyph
        color: chip.enabledValue ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        opacity: chip.enabledValue ? 1.0 : 0.6
      }

      Text {
        visible: chip.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        color: chip.enabledValue ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: chip.hoveredChip()
      onClicked: chip.clicked()
    }
  }

  component PackRow: CursorSurface {
    id: packRow

    property var pack: null
    readonly property string packName: pack ? String(pack.name) : ""

    hasCursor: root.cursorId === "pack:" + packName
    foreground: root.foreground
    implicitHeight: packContent.implicitHeight + Style.space(12)

    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(packRow)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: root.setCursorTo("pack", packRow.packName)
    }

    Row {
      id: packContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰏗"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Column {
        width: parent.width - Style.font.icon - updateButton.width - removeButton.width - parent.spacing * 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: packRow.packName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: (packRow.pack ? packRow.pack.actions : 0)
            + (packRow.pack && packRow.pack.actions === 1 ? " action" : " actions")
            + " · Enter updates · x removes"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: updateButton
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰑐"
        tooltipText: "git pull this pack"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !(root.blip && root.blip.packBusy)
        onClicked: if (root.blip) root.notePackResult(root.blip.packUpdate(packRow.packName))
      }

      PanelActionButton {
        id: removeButton
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰩺"
        tooltipText: "Remove this pack"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !(root.blip && root.blip.packBusy)
        onClicked: if (root.blip) root.notePackResult(root.blip.packRemove(packRow.packName))
      }
    }
  }
}
