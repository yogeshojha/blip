import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Transforms.js" as Transforms

Item {
  id: root

  property var service: null

  property bool opened: false
  property bool keyboardActive: false
  property bool trusted: false
  readonly property bool adopted: trusted || keyboardActive || hover.hovered
  property var detection: null
  property var visibleActions: []
  property var overflowActions: []
  property int cursorX: 0
  property int cursorY: 0

  // -1 selects nothing.
  property int index: 0
  property bool navigated: false
  property bool expanded: false
  property var result: null
  property var pendingConfirm: null
  property string notice: ""
  property bool busy: false

  property bool focusPrimed: false
  property bool morphEnabled: false

  // Moved forward on every change a click could be racing; see pressPointer.
  property double quietUntil: 0
  readonly property int settleMs: 350

  // Set before opened changes: the animations read it as they start, and a
  // binding on opened alone has not always caught up by then.
  property bool entering: false
  readonly property int exitMs: 130

  signal runRequested(var action)
  signal copyRequested(string text)
  signal replaceRequested(string text)

  readonly property var rows: expanded ? visibleActions.concat(overflowActions) : visibleActions
  readonly property bool hasOverflow: overflowActions.length > 0
  readonly property bool moreReachable: hasOverflow && !expanded
  readonly property bool moreSelected: moreReachable && index === rows.length
  readonly property string mode: result ? "result" : (pendingConfirm ? "confirm" : "actions")
  readonly property bool resultIsQr: !!result && result.render === "qr"
  readonly property bool resultCanReplace: !!result && result.replace === true
  readonly property bool confirmNetwork: !!pendingConfirm && pendingConfirm.needsConsent === true

  // Replace and Copy sit side by side in a result; 0 is Replace, 1 is Copy.
  property int resultIndex: 0
  readonly property bool resultChoosing: mode === "result" && resultCanReplace
  readonly property string typeLabel: detection ? String(detection.primaryLabel || "") : ""

  // The accelerators run unfocused too, so the badges follow those, not the focus.
  readonly property bool keysLive: opened && (keyboardActive || (mode === "actions" && adopted))

  readonly property int pad: Style.spacing.popupPadding
  readonly property int gap: Style.spacing.sm
  readonly property int chipHeight: Math.max(Style.spacing.controlHeight, Style.font.body + Style.spacing.controlPaddingY * 2)
  readonly property int cursorGap: Style.space(18)
  readonly property int edgeGap: Math.max(Style.gapsOut, Style.space(6))
  readonly property int listWidth: Style.space(380)
  readonly property int maxBodyWidth: Style.space(720)
  readonly property int maxBodyHeight: Style.space(420)
  readonly property int maxListHeight: Style.space(420)

  readonly property color ink: Color.popups.text
  readonly property color faint: Util.alpha(ink, 0.55)
  readonly property string fontFamily: Style.font.menuFamily

  // Only 6-digit hex: Qt reads #RRGGBBAA as #AARRGGBB.
  readonly property string swatchColor: detection && detection.primary === "color"
    && /^#[0-9A-Fa-f]{6}$/.test(detection.value) ? detection.value : ""

  readonly property var answer: detection ? Transforms.instant(detection, Date.now()) : null

  function present(nextDetection, menu, x, y, focus, trust) {
    trusted = trust === true
    detection = nextDetection
    visibleActions = menu.visible
    overflowActions = menu.overflow
    cursorX = x
    cursorY = y
    index = focus === true ? 0 : -1
    navigated = false
    expanded = false
    listWidthFloor = 0
    result = null
    resultIndex = 0
    pendingConfirm = null
    notice = ""
    busy = false
    morphEnabled = false
    morphTimer.restart()
    quietUntil = Date.now() + settleMs
    entering = true
    opened = true
    setKeyboard(focus === true)
  }

  function close() {
    if (!opened) return
    entering = false
    opened = false
    keyboardActive = false
    trusted = false
    focusPrimed = false
    busy = false
    morphEnabled = false
    primeTimer.stop()
    morphTimer.stop()
    dwellTimer.stop()
    noticeTimer.stop()
  }

  function setKeyboard(active) {
    keyboardActive = active
    if (active) {
      if (index < 0) index = 0
      focusPrimed = false
      primeTimer.restart()
      Qt.callLater(function() { keys.forceActiveFocus() })
    } else {
      primeTimer.stop()
      focusPrimed = false
    }
    restartDwell()
  }

  function restartDwell() {
    if (!opened || keyboardActive || hover.hovered || expanded || result || pendingConfirm || busy) {
      dwellTimer.stop()
      return
    }
    dwellTimer.restart()
  }

  function move(delta) {
    var count = rows.length + (moreReachable ? 1 : 0)
    if (!count) return
    if (index < 0) { index = delta > 0 ? 0 : count - 1; return }
    index = (index + delta + count) % count
  }

  function activate() {
    quietUntil = Date.now() + settleMs
    if (moreSelected) { setExpanded(true); return }
    var action = rows[index]
    if (!action || busy) return
    if ((action.confirm || action.needsConsent) && !pendingConfirm) {
      pendingConfirm = action
      holdKeyboard()
      return
    }
    pendingConfirm = null
    busy = true
    dwellTimer.stop()
    runRequested(action)
  }

  function activateByKey(letter) {
    var i
    for (i = 0; i < rows.length; i++) {
      if (rows[i].accelerator !== letter) continue
      index = i
      activate()
      return true
    }
    if (expanded || !hasOverflow) return false
    for (i = 0; i < overflowActions.length; i++) {
      if (overflowActions[i].accelerator !== letter) continue
      expanded = true
      index = visibleActions.length + i
      activate()
      return true
    }
    return false
  }

  function showResult(payload) {
    quietUntil = Date.now() + settleMs
    busy = false
    replaced = false
    resultIndex = 0
    result = payload
    holdKeyboard()
  }

  // Grabbing here would drop the service's binds for a focus we may not be granted.
  function holdKeyboard() {
    if (keyboardActive || (service && service.grabKeyboard)) setKeyboard(true)
    else restartDwell()
  }

  function moveResult(delta) {
    if (!resultChoosing) return false
    resultIndex = (resultIndex + delta + 2) % 2
    return true
  }

  // Routed in from the service's binds; each mirrors a branch of the focused handler.
  function pressReturn() {
    if (result) {
      if (resultChoosing && resultIndex === 1) copyRequested(result.copy)
      else if (!replaceResult()) copyRequested(result.copy)
      return true
    }
    activate()
    return true
  }

  property bool replaced: false

  function replaceResult() {
    if (!resultCanReplace || replaced) return false
    replaced = true
    replaceRequested(result.copy)
    return true
  }

  function pressTab() {
    if (result) return moveResult(1)
    if (!hasOverflow) return false
    navigated = true
    setExpanded(!expanded)
    return true
  }

  // Left and right only: up and down stay dismiss keys, so history and scroll survive.
  function pressMove(delta) {
    if (result) return moveResult(delta)
    if (pendingConfirm || !rows.length) return false
    move(delta)
    navigated = true
    return true
  }

  function pressAnswer() {
    if (!answer) return false
    copyRequested(answer.copy)
    return true
  }

  // Routed in from the service's mouse binds: outside the card the bar has no input.
  function pressPointer(button) {
    if (!opened) return false
    // A context menu is on its way up and the bar, on the overlay layer, covers it.
    if (button === "right") { close(); return true }
    if (hover.hovered) return false
    // Clicks widen a selection press by press: the second must not close the first.
    if (Date.now() < quietUntil) return false
    close()
    return true
  }

  function copyResult() {
    if (!result) return false
    copyRequested(result.copy)
    return true
  }

  // Also drops the result: Enter during the notice must not fire a replace.
  function flash(message) {
    quietUntil = Date.now() + settleMs
    busy = false
    result = null
    notice = message
    dwellTimer.stop()
    noticeTimer.restart()
  }

  function back() {
    if (result) { result = null; restartDwell(); return }
    if (pendingConfirm) { pendingConfirm = null; restartDwell(); return }
    if (expanded) { setExpanded(false); return }
    close()
  }

  function setExpanded(value) {
    if (value === true && !expanded) listWidthFloor = content.implicitWidth
    expanded = value === true
    if (expanded) index = index < 0 ? 0 : Math.min(index, rows.length - 1)
    else if (!navigated) index = -1
    // Collapsing from an overflow row lands back on the ⋯ chip.
    else index = Math.min(Math.max(index, 0), rows.length - 1 + (moreReachable ? 1 : 0))
  }

  property int listWidthFloor: 0

  onModeChanged: if (opened) swapFade.restart()
  onExpandedChanged: {
    if (opened) swapFade.restart()
    restartDwell()
  }
  onNoticeChanged: if (opened && notice !== "") swapFade.restart()

  Timer {
    id: dwellTimer
    interval: root.service ? root.service.dwellMs : 4000
    onTriggered: root.close()
  }

  Timer {
    id: noticeTimer
    interval: 850
    onTriggered: root.close()
  }

  Timer {
    id: primeTimer
    interval: 75
    onTriggered: if (root.opened && root.keyboardActive) root.focusPrimed = true
  }

  Timer {
    id: morphTimer
    interval: 200
    onTriggered: root.morphEnabled = root.opened
  }

  readonly property bool watchingAway: opened && !keyboardActive
    && (mode === "actions" || mode === "result") && !busy && !hover.hovered

  function checkAway(raw) {
    if (!watchingAway) return
    var parts = String(raw || "").split(",")
    var px = Number(parts[0])
    var py = Number(parts[1])
    if (!isFinite(px) || !isFinite(py)) return
    var reach = Style.space(200)
    var screenX = targetScreen ? targetScreen.x : 0
    var screenY = targetScreen ? targetScreen.y : 0
    var overX = Math.max(screenX + card.x - px, 0, px - (screenX + card.x + card.width))
    var overY = Math.max(screenY + card.y - py, 0, py - (screenY + card.y + card.height))
    if (Math.hypot(px - cursorX, py - cursorY) > reach && Math.hypot(overX, overY) > reach) close()
  }

  Timer {
    interval: 300
    repeat: true
    running: root.watchingAway
    onTriggered: if (!awayProbe.running) awayProbe.running = true
  }

  Process {
    id: awayProbe
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.checkAway(text)
    }
  }

  readonly property var targetScreen: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      var candidate = screens[i]
      if (cursorX >= candidate.x && cursorX < candidate.x + candidate.width
          && cursorY >= candidate.y && cursorY < candidate.y + candidate.height) return candidate
    }
    return screens.length ? screens[0] : null
  }

  readonly property bool centred: service ? service.centred : false
  readonly property int localX: cursorX - (targetScreen ? targetScreen.x : 0)
  readonly property int localY: cursorY - (targetScreen ? targetScreen.y : 0)

  readonly property int cardX: {
    if (centred || panel.width <= 0) return Math.round((panel.width - card.width) / 2)
    return Math.round(Math.max(edgeGap, Math.min(localX - card.width / 2, panel.width - card.width - edgeGap)))
  }

  // From the pointer alone, so unfolding cannot flip the card mid-flight.
  readonly property bool placeAbove: localY >= panel.height * 0.45

  readonly property int cardY: {
    if (centred || panel.height <= 0) return Math.round((panel.height - card.height) / 2)
    if (placeAbove) return Math.round(Math.max(edgeGap, localY - cursorGap - card.height))
    return Math.round(Math.max(edgeGap, Math.min(localY + cursorGap, panel.height - card.height - edgeGap)))
  }

  PanelWindow {
    id: panel

    visible: root.opened || card.opacity > 0
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "blip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && root.keyboardActive
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: root.opened ? card : null }

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: root.keyboardActive

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.pressReturn()
          event.accepted = true
          return
        }
        // Space stays a copy: a reflex press must never rewrite the selection.
        if (event.key === Qt.Key_Space) {
          if (!root.copyResult()) root.activate()
          event.accepted = true
          return
        }
        if (root.result) {
          if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            if (root.moveResult(-1)) event.accepted = true
            return
          }
          if (event.key === Qt.Key_Right || event.key === Qt.Key_Down
              || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            if (root.moveResult(1)) event.accepted = true
            return
          }
          if (event.text === "c") { root.copyResult(); event.accepted = true; return }
          if (event.text === "r" && root.replaceResult()) event.accepted = true
          return
        }
        if (root.pendingConfirm) return
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          if (root.hasOverflow) root.setExpanded(!root.expanded)
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) { root.move(1); event.accepted = true; return }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) { root.move(-1); event.accepted = true; return }
        if (root.answer && event.text === "=") {
          root.copyRequested(root.answer.copy)
          event.accepted = true
          return
        }
        if (event.text && event.text.length === 1 && root.activateByKey(event.text.toLowerCase()))
          event.accepted = true
      }
    }

    BorderSurface {
      id: card

      x: root.cardX
      y: root.cardY
      width: content.implicitWidth + card.contentLeftInset + card.contentRightInset
      height: content.implicitHeight + card.contentTopInset + card.contentBottomInset
      padding: root.pad
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.94
      transformOrigin: Item.Center

      transform: Translate {
        y: root.opened ? 0 : (root.placeAbove ? Style.space(6) : -Style.space(6))

        Behavior on y {
          NumberAnimation {
            duration: root.entering ? 200 : root.exitMs
            easing.type: root.entering ? Easing.OutCubic : Easing.InOutQuad
          }
        }
      }

      // Linear out: an eased fade is mostly over in 40ms, and reads as a blink.
      Behavior on opacity {
        NumberAnimation {
          duration: root.entering ? 150 : root.exitMs
          easing.type: root.entering ? Easing.OutCubic : Easing.Linear
        }
      }
      Behavior on scale {
        NumberAnimation {
          duration: root.entering ? 260 : root.exitMs
          easing.type: root.entering ? Easing.OutBack : Easing.InOutQuad
          easing.overshoot: 1.4
        }
      }

      // Only the size animates: x and y derive from it and track in sync.
      Behavior on width { enabled: root.morphEnabled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on height { enabled: root.morphEnabled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      HoverHandler {
        id: hover
        onHoveredChanged: root.restartDwell()
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        implicitWidth: stack.implicitWidth
        implicitHeight: stack.implicitHeight
        clip: true

        Column {
          id: stack
          spacing: root.gap

          SequentialAnimation {
            id: swapFade

            PropertyAction { target: stack; property: "opacity"; value: 0 }
            PauseAnimation { duration: 70 }
            NumberAnimation {
              target: stack
              property: "opacity"
              to: 1
              duration: 140
              easing.type: Easing.OutCubic
            }
          }

          Loader {
            active: root.notice !== ""
            visible: active
            sourceComponent: noticeView
          }

          Loader {
            active: root.notice === "" && root.mode === "actions" && !root.expanded
            visible: active
            sourceComponent: chipRow
          }

          Loader {
            active: root.notice === "" && root.mode === "actions" && root.expanded
            visible: active
            sourceComponent: actionList
          }

          Loader {
            active: root.notice === "" && root.mode === "actions" && root.keysLive
            visible: active
            sourceComponent: keyHint
          }

          Loader {
            active: root.notice === "" && root.mode === "confirm"
            visible: active
            sourceComponent: confirmView
          }

          Loader {
            active: root.notice === "" && root.mode === "result"
            visible: active
            sourceComponent: resultView
          }
        }
      }

      Item {
        id: busyTrack
        visible: root.busy
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: Math.max(Style.space(4), Math.round(card.contentBottomInset / 3))
        height: Math.max(2, Style.space(2))
        clip: true

        Rectangle {
          id: busyDash
          width: Math.max(Style.space(24), busyTrack.width * 0.3)
          height: parent.height
          radius: height / 2
          color: Color.accent

          NumberAnimation on x {
            running: root.busy && panel.visible
            loops: Animation.Infinite
            from: -busyDash.width
            to: busyTrack.width
            duration: 900
            easing.type: Easing.InOutQuad
          }
        }
      }
    }
  }

  Component {
    id: noticeView

    Row {
      id: noticeRow
      spacing: Style.spacing.sm
      opacity: 0
      scale: 0.9
      Component.onCompleted: { opacity = 1; scale = 1 }

      Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.notice === "Copied" ? "󰄬" : "󰋽"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.notice
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }
  }

  Component {
    id: chipRow

    Item {
      id: chipStrip
      implicitWidth: strip.implicitWidth
      implicitHeight: strip.implicitHeight

      readonly property Item selChip: {
        var deps = root.index + chipRepeater.count
        if (root.moreSelected) return moreChip
        return chipRepeater.itemAt(root.index)
      }

      // The one selection surface; entrance opacity and scale follow the chip.
      BorderSurface {
        id: glide
        visible: chipStrip.selChip !== null
        x: chipStrip.selChip ? chipStrip.selChip.x : 0
        y: chipStrip.selChip ? chipStrip.selChip.y : 0
        width: chipStrip.selChip ? chipStrip.selChip.width : 0
        height: chipStrip.selChip ? chipStrip.selChip.height : 0
        opacity: chipStrip.selChip ? chipStrip.selChip.opacity : 0
        scale: chipStrip.selChip ? chipStrip.selChip.scale : 1
        transformOrigin: Item.Center
        radius: Style.cornerRadius
        color: Style.selectedFillFor(root.ink, Color.accent)
        borderSpec: Border.controlSpec("selected", root.ink, Color.accent)

        Behavior on x { enabled: root.morphEnabled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: root.morphEnabled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      Row {
        id: strip
        spacing: root.gap

        Rectangle {
          id: badge
        visible: root.typeLabel !== ""
        width: badgeContent.implicitWidth + Style.spacing.controlPaddingX * 2
        height: root.chipHeight
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: Util.alpha(Color.accent, 0.14)
        opacity: 0
        Component.onCompleted: opacity = 1

        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Row {
          id: badgeContent
          anchors.centerIn: parent
          spacing: Style.spacing.xs

          Rectangle {
            visible: root.swatchColor !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(10)
            height: width
            radius: width / 2
            color: root.swatchColor !== "" ? root.swatchColor : "transparent"
            border.width: 1
            border.color: Util.alpha(root.ink, 0.35)
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.typeLabel
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      BorderSurface {
        id: answerPill
        visible: root.answer !== null
        width: answerText.implicitWidth + Style.spacing.controlPaddingX * 2
        height: root.chipHeight
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: Util.alpha(root.ink, 0.05)
        borderSpec: Border.controlSpec(answerHover.hovered ? "hover-cursor" : "normal", root.ink, Color.accent)
        opacity: 0
        Component.onCompleted: opacity = 1

        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Text {
          id: answerText
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.answer ? root.answer.text : ""
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        HoverHandler {
          id: answerHover
          cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
          onTapped: if (root.answer) root.copyRequested(root.answer.copy)
        }

        PanelToolTip {
          visible: answerHover.hovered
          text: "Click to copy"
          fontFamily: root.fontFamily
        }
      }

      Repeater {
        id: chipRepeater
        model: root.visibleActions

        Chip {
          id: chip
          action: modelData
          selected: root.index === index
          paintSelection: false
          showKey: root.keysLive
          onClicked: { root.index = index; root.activate() }
          onHovered: root.index = index

          opacity: 0
          scale: 0.9
          transformOrigin: Item.Center
          Component.onCompleted: chipIntro.restart()

          SequentialAnimation {
            id: chipIntro
            PauseAnimation { duration: 24 * index }
            ParallelAnimation {
              NumberAnimation { target: chip; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
              NumberAnimation { target: chip; property: "scale"; to: 1; duration: 170; easing.type: Easing.OutCubic }
            }
          }
        }
      }

      Chip {
        id: moreChip
        visible: root.hasOverflow
        overflowGlyph: "⋯"
        showKey: root.keysLive
        selected: root.moreSelected
        paintSelection: false
        onHovered: root.index = root.visibleActions.length
        onClicked: { root.index = root.visibleActions.length; root.setExpanded(true) }

        opacity: 0
        scale: 0.9
        transformOrigin: Item.Center
        Component.onCompleted: moreIntro.restart()

        SequentialAnimation {
          id: moreIntro
          PauseAnimation { duration: 24 * root.visibleActions.length }
          ParallelAnimation {
            NumberAnimation { target: moreChip; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
            NumberAnimation { target: moreChip; property: "scale"; to: 1; duration: 170; easing.type: Easing.OutCubic }
          }
        }
      }
      }
    }
  }

  Component {
    id: actionList

    Item {
      id: listBox
      implicitWidth: Math.min(Math.max(root.listWidth, root.listWidthFloor), root.maxBodyWidth)
      implicitHeight: Math.min(listColumn.implicitHeight, root.maxListHeight)

      readonly property Item selRow: {
        var deps = root.index + rowRepeater.count
        return rowRepeater.itemAt(root.index)
      }

      Flickable {
        id: listFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: listColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        CursorSurface {
          id: listGlide
          visible: listBox.selRow !== null
          x: 0
          width: listColumn.width
          y: listBox.selRow ? listBox.selRow.y : 0
          height: listBox.selRow ? listBox.selRow.height : 0
          hasCursor: true
          foreground: root.ink

          Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        Column {
          id: listColumn
          width: listFlick.width
          spacing: Style.spacing.xxs

          Repeater {
            id: rowRepeater
            model: root.rows

            ActionRow {
              width: listColumn.width
              action: modelData
              selected: root.index === index
              paintSelection: false
              showKey: root.keysLive
              onClicked: { root.index = index; root.activate() }
              onHovered: root.index = index
            }
          }
        }

        Connections {
          target: root
          function onIndexChanged() {
            if (!root.expanded || listFlick.contentHeight <= listFlick.height) return
            var item = listColumn.children[root.index]
            if (!item || !item.height) return
            var margin = Style.space(4)
            if (item.y < listFlick.contentY + margin)
              listFlick.contentY = Math.max(0, item.y - margin)
            else if (item.y + item.height > listFlick.contentY + listFlick.height - margin)
              listFlick.contentY = Math.min(listFlick.contentHeight - listFlick.height,
                                            item.y + item.height + margin - listFlick.height)
          }
        }
      }
    }
  }

  Component {
    id: keyHint

    Text {
      textFormat: Text.PlainText
      text: root.expanded
        ? "Enter runs · Tab collapses · Esc closes"
        : "Letters run · Tab for all · Esc closes"
      color: Util.alpha(root.ink, 0.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Component {
    id: confirmView

    Column {
      spacing: Style.spacing.md

      Row {
        spacing: Style.spacing.sm

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "󰀦"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: root.confirmNetwork
            ? (root.pendingConfirm.label + " sends this selection over the network")
            : "Run this as a command?"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
      }

      Text {
        textFormat: Text.PlainText
        width: Math.min(implicitWidth, root.listWidth)
        text: root.confirmNetwork
          ? (root.pendingConfirm.host ? "to " + root.pendingConfirm.host : "to an undeclared host")
          : (root.detection ? root.detection.value : "")
        color: root.ink
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: root.confirmNetwork
          ? "Enter to allow it from now on · Esc to cancel"
          : "Enter to run · Esc to cancel"
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component {
    id: resultView

    Column {
      spacing: Style.spacing.md

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        anchors.horizontalCenter: root.resultIsQr ? parent.horizontalCenter : undefined
        text: root.result ? String(root.result.title || "") : ""
        color: root.result && root.result.tone === "urgent" ? Color.urgent : Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Loader {
        active: root.resultIsQr
        visible: active
        anchors.horizontalCenter: parent.horizontalCenter
        sourceComponent: codeView
      }

      Loader {
        active: !root.resultIsQr
        visible: active
        sourceComponent: textView
      }

      Text {
        textFormat: Text.PlainText
        visible: !root.resultCanReplace
        anchors.horizontalCenter: root.resultIsQr ? parent.horizontalCenter : undefined
        text: root.resultIsQr ? "Enter to copy the link · Esc to close" : "Enter to copy · Esc to close"
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        visible: root.resultCanReplace
        spacing: Style.spacing.sm

        Chip {
          action: ({ label: "Replace", accelerator: root.resultIndex === 0 ? "⏎" : "r" })
          selected: root.resultIndex === 0
          showKey: true
          onClicked: { root.resultIndex = 0; root.replaceResult() }
          onHovered: root.resultIndex = 0
        }

        Chip {
          action: ({ label: "Copy", accelerator: root.resultIndex === 1 ? "⏎" : "c" })
          selected: root.resultIndex === 1
          showKey: true
          onClicked: { root.resultIndex = 1; root.copyResult() }
          onHovered: root.resultIndex = 1
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "← → choose · Esc closes"
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Component {
    id: codeView

    Rectangle {
      implicitWidth: code.width + Style.space(12) * 2
      implicitHeight: code.height + Style.space(12) * 2
      radius: Style.cornerRadius > 0 ? Style.space(10) : 0
      color: "white"

      opacity: 0
      scale: 0.92
      transformOrigin: Item.Center
      Component.onCompleted: { opacity = 1; scale = 1 }

      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

      Image {
        id: code
        anchors.centerIn: parent
        source: root.result ? "data:image/png;base64," + root.result.body : ""
        fillMode: Image.PreserveAspectFit
        width: Math.min(sourceSize.width, Style.space(260))
        height: width
        smooth: false
      }
    }
  }

  Component {
    id: textView

    Item {
      implicitWidth: Math.min(Math.max(body.implicitWidth, Style.space(180)), root.maxBodyWidth)
      implicitHeight: Math.min(body.implicitHeight, root.maxBodyHeight)

      opacity: 0
      transform: Translate {
        id: bodyRise
        y: Style.space(5)

        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      }
      Component.onCompleted: { opacity = 1; bodyRise.y = 0 }

      Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

      Flickable {
        anchors.fill: parent
        contentWidth: body.implicitWidth
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Text {
          id: body
          text: root.result ? String(root.result.body || "") : ""
          color: root.ink
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          lineHeightMode: Text.FixedHeight
          lineHeight: Math.round(Style.font.body * 1.45)
          textFormat: Text.PlainText
        }
      }
    }
  }
}
