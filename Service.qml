import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Detect.js" as Detect
import "Actions.js" as Actions
import "Transforms.js" as Transforms

Item {
  id: service

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "yogeshojha.blip"
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string userDir: home + "/.config/omarchy/blip"

  readonly property var settings: {
    var config = shell ? shell.shellConfig : null
    return Util.isPlainObject(config) ? entryFor(config) : ({})
  }

  function entryFor(config) {
    var sections = ["left", "center", "right"]
    var layout = Util.isPlainObject(config.bar) ? config.bar.layout : null
    for (var s = 0; s < sections.length; s++) {
      var list = Util.isPlainObject(layout) ? layout[sections[s]] : null
      if (!Array.isArray(list)) continue
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].id) === pluginId) return list[i]
      }
    }
    if (Array.isArray(config.plugins)) {
      for (var j = 0; j < config.plugins.length; j++) {
        if (config.plugins[j] && String(config.plugins[j].id) === pluginId) return config.plugins[j]
      }
    }
    return ({})
  }

  function setting(key) {
    var value = settings ? settings[key] : undefined
    if (value !== undefined && value !== null) return value
    var defaults = manifest && Util.isPlainObject(manifest.barWidget) ? manifest.barWidget.defaults : null
    return defaults ? defaults[key] : undefined
  }

  function persist(key, value) {
    if (!shell || typeof shell.updateEntryInline !== "function") return
    var next = {}
    for (var existing in settings) next[existing] = settings[existing]
    next[key] = value
    shell.updateEntryInline(pluginId, next)
  }

  readonly property bool armed: setting("armed") !== false
  readonly property bool automatic: String(setting("trigger")) !== "Keybind only"
  readonly property bool grabKeyboard: setting("grabKeyboard") === true
  readonly property bool centred: String(setting("position")) === "Screen centre"
  readonly property bool allowNetwork: setting("allowNetwork") === true
  readonly property bool pauseWhenSharing: setting("pauseWhenSharing") !== false
  readonly property bool showIndicator: setting("showIndicator") !== false
  readonly property int minLength: Math.max(1, Number(setting("minLength")) || 2)
  readonly property int maxLength: Math.max(200, Number(setting("maxLength")) || 20000)
  readonly property int maxActions: Math.max(1, Number(setting("maxActions")) || 6)
  readonly property int debounceMs: Math.max(0, Number(setting("debounceMs")) || 0)
  readonly property int dwellMs: Math.max(1, Number(setting("dwellSeconds")) || 4) * 1000
  readonly property var blocklist: {
    var raw = String(setting("blockedApps") || "").split(",")
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var entry = raw[i].replace(/^\s+|\s+$/g, "").toLowerCase()
      if (entry.length) out.push(entry)
    }
    return out
  }

  readonly property var disabledSet: {
    var raw = String(setting("disabledActions") || "").split(",")
    var out = ({})
    for (var i = 0; i < raw.length; i++) {
      var id = raw[i].replace(/^\s+|\s+$/g, "")
      if (id.length) out[id] = true
    }
    return out
  }

  function isActionEnabled(id) {
    return disabledSet[String(id)] !== true
  }

  function setActionsEnabled(ids, enabled) {
    var next = ({})
    for (var key in disabledSet) next[key] = true
    for (var i = 0; i < ids.length; i++) {
      if (enabled) delete next[String(ids[i])]
      else next[String(ids[i])] = true
    }
    var list = []
    for (var id in next) list.push(id)
    list.sort()
    persist("disabledActions", list.join(","))
  }

  function setActionEnabled(id, enabled) {
    setActionsEnabled([id], enabled)
  }

  property string selection: ""
  property string lastApp: ""
  property bool sharing: false
  property bool skipFirstEvent: true
  property var pending: null

  property var fileEntries: []
  property var runtimeEntries: []
  property var consented: ({})
  property var catalogErrors: []

  readonly property var catalog: Actions.mergeCatalog(fileEntries.concat(runtimeEntries))
  readonly property var activeCatalog: {
    var out = []
    for (var i = 0; i < catalog.length; i++) {
      if (disabledSet[catalog[i].id] !== true) out.push(catalog[i])
    }
    return out
  }
  readonly property var modules: Actions.groupCatalog(catalog)
  readonly property bool suppressed: sharing && pauseWhenSharing

  // ---------------------------------------------------------------- packs
  // A pack is a git repository under ~/.config/omarchy/blip/packs/.

  property var installedPacks: []
  property bool packBusy: false
  property string packStatus: ""
  property bool packStatusUrgent: false

  readonly property var packList: {
    var out = []
    for (var i = 0; i < installedPacks.length; i++) {
      var pack = installedPacks[i]
      var marker = "/packs/" + pack.name + "/"
      var count = 0
      for (var j = 0; j < catalog.length; j++) {
        if (catalog[j].origin === "pack" && String(catalog[j].source).indexOf(marker) !== -1) count++
      }
      out.push({ name: pack.name, path: pack.path, actions: count })
    }
    return out
  }

  function hasPack(name) {
    for (var i = 0; i < installedPacks.length; i++) {
      if (installedPacks[i].name === name) return true
    }
    return false
  }

  function packAdd(source) {
    var src = String(source || "").replace(/^\s+|\s+$/g, "")
    if (packBusy) return "error: another pack operation is running"
    if (!Actions.isPackSource(src)) return "error: packs install from an https:// git url or an absolute local path"
    var name = Actions.packNameFromSource(src)
    if (!name) return "error: cannot derive a pack name from '" + src + "'"
    if (hasPack(name)) return "error: pack '" + name + "' is already installed"
    // Staged in a dot-prefixed dir the scanner skips, moved into place in
    // one step, so the catalog never sees half a pack.
    var dest = userDir + "/packs/" + name
    var staging = userDir + "/packs/.staging-" + name
    runPack("add", name, ["bash", "-c",
      'set -e; [ ! -e "$2" ] || { echo "a pack named $(basename -- "$2") is already installed" >&2; exit 1; }; '
      + 'rm -rf -- "$1"; git clone --depth 1 -- "$0" "$1"; mv -T -- "$1" "$2"',
      src, staging, dest])
    return "installing " + name
  }

  function packUpdate(name) {
    var key = String(name || "").replace(/^\s+|\s+$/g, "")
    if (packBusy) return "error: another pack operation is running"
    if (!Actions.isPackName(key) || !hasPack(key)) return "error: no pack named '" + key + "'"
    runPack("update", key, ["git", "-C", userDir + "/packs/" + key, "pull", "--ff-only"])
    return "updating " + key
  }

  function packRemove(name) {
    var key = String(name || "").replace(/^\s+|\s+$/g, "")
    if (packBusy) return "error: another pack operation is running"
    if (!Actions.isPackName(key) || !hasPack(key)) return "error: no pack named '" + key + "'"
    runPack("remove", key, ["rm", "-rf", "--", userDir + "/packs/" + key])
    return "removing " + key
  }

  function runPack(op, name, argv) {
    packBusy = true
    packStatusUrgent = false
    packStatus = (op === "add" ? "Installing " : op === "update" ? "Updating " : "Removing ") + name + "…"
    packStatusClear.stop()
    packProc.op = op
    packProc.packName = name
    packProc.timedOut = false
    packProc.command = argv
    packProc.running = true
  }

  Process {
    id: packProc

    property string op: ""
    property string packName: ""
    property bool timedOut: false

    stderr: StdioCollector { id: packErr; waitForEnd: true }
    onExited: function(exitCode) {
      service.packBusy = false
      if (timedOut) {
        service.packStatus = packName + ": gave up after 2 minutes"
        service.packStatusUrgent = true
      } else if (exitCode === 0) {
        service.packStatus = (op === "add" ? "Installed " : op === "update" ? "Updated " : "Removed ") + packName
        service.packStatusUrgent = false
      } else {
        var lines = String(packErr.text || "").replace(/\s+$/, "").split("\n")
        service.packStatus = packName + ": " + (lines[lines.length - 1] || "failed")
        service.packStatusUrgent = true
      }
      service.rescan()
      packStatusClear.restart()
    }
  }

  // A clone against a dead network would otherwise hold packBusy forever.
  Timer {
    running: packProc.running
    interval: 120000
    onTriggered: {
      packProc.timedOut = true
      packProc.running = false
    }
  }

  Timer {
    id: packStatusClear
    interval: 8000
    onTriggered: service.packStatus = ""
  }

  function setArmed(value) {
    if (!value) {
      popup.close()
      selection = ""
    }
    persist("armed", value === true)
  }

  function toggleArmed() {
    setArmed(!armed)
  }

  function openActionsDir() {
    Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && xdg-open "$1"', "blip", userDir + "/actions"])
  }

  function isBlocked(text) {
    var haystack = String(text || "").toLowerCase()
    if (!haystack.length) return false
    for (var i = 0; i < blocklist.length; i++) {
      if (haystack.indexOf(blocklist[i]) !== -1) return true
    }
    return false
  }

  function onSelectionLine(line) {
    var encoded = String(line || "").replace(/^\s+|\s+$/g, "")
    if (skipFirstEvent) {
      skipFirstEvent = false
      return
    }
    if (!encoded.length) {
      if (popup.opened && popup.mode === "actions" && !popup.keyboardActive && !popup.busy)
        popup.close()
      return
    }
    var text = Transforms.utf8(Transforms.decodeBase64(encoded))
    if (!text || !text.length) return
    selection = text
    if (!automatic) return
    popup.close()
    debounce.restart()
  }

  function present(text, focus) {
    if (!armed) return "disarmed"
    if (suppressed) return "sharing"
    var value = String(text || "")
    if (value.replace(/^\s+|\s+$/g, "").length < minLength) return "too short"
    if (value.length > maxLength) return "too long"
    pending = { text: value, focus: focus === true }
    // Keep the cached sharing state fresh without holding up the cursor read.
    if (pauseWhenSharing && !sharingProbe.running) sharingProbe.running = true
    if (!probe.running) probe.running = true
    return "ok"
  }

  function applyProbe(raw) {
    var request = pending
    pending = null
    if (!request) return

    var lines = String(raw || "").split("\n")
    var point = String(lines[0] || "").split(",")
    var x = Math.round(Number(point[0]))
    var y = Math.round(Number(point[1]))
    var window = String(lines[1] || "").split("\t")
    lastApp = window[0] || ""

    if (!armed || suppressed) return
    if (isBlocked(lastApp) || isBlocked(window[1] || "")) return

    var detection = Detect.detect(request.text)
    detection.primaryLabel = Detect.label(detection.primary)
    detection.home = home

    var menu = Actions.build(activeCatalog, detection, {
      app: lastApp,
      allowNetwork: allowNetwork,
      limit: maxActions
    })
    if (!menu.all.length) return

    for (var i = 0; i < menu.all.length; i++) {
      var entry = menu.all[i]
      entry.needsConsent = entry.network && consented[entry.id] !== true
      entry.host = entry.network ? Actions.hostOf(entry, detection) : ""
    }

    popup.present(detection, menu, isFinite(x) ? x : 0, isFinite(y) ? y : 0, request.focus || grabKeyboard)
  }

  Timer {
    id: debounce
    interval: service.debounceMs
    onTriggered: service.present(service.selection, false)
  }

  Process {
    id: watcher
    command: [
      "setpriv", "--pdeathsig", "TERM",
      "wl-paste", "--primary", "--type", "text", "--watch",
      "bash", "-c",
      "[[ ${CLIPBOARD_STATE:-} == sensitive ]] && exit 0; head -c 400000 | base64 -w0; echo"
    ]
    stdout: SplitParser {
      onRead: function(line) { service.onSelectionLine(line) }
    }
    onRunningChanged: if (running) service.skipFirstEvent = true
    onExited: if (service.armed) watcherRestart.restart()
  }

  Timer {
    id: watcherRestart
    interval: 1000
    onTriggered: watcher.running = service.armed
  }

  onArmedChanged: watcher.running = armed
  Component.onCompleted: {
    watcher.running = armed
    // A crash skips onDestruction, so sweep the consuming set at startup too.
    passiveKeys.sweep()
  }

  readonly property string sharingScript: ""
    + "pgrep -x 'gpu-screen-recorder|wf-recorder' >/dev/null && exit 0; "
    + "command -v pw-dump >/dev/null || exit 1; "
    + "pw-dump 2>/dev/null | jq -e 'any(.[]?; "
    + ".info.props[\"media.class\"] == \"Stream/Output/Video\" and "
    + "((.info.props[\"node.name\"] // \"\") | test(\"xdpw|screen|cast\"; \"i\")))' >/dev/null"

  Process {
    id: probe
    command: ["bash", "-c",
      "hyprctl cursorpos; "
      + "hyprctl -j activewindow | jq -r '(.class // \"\") + \"\\t\" + (.title // \"\")'"]
    stdout: StdioCollector {
      id: probeOut
      waitForEnd: true
      onStreamFinished: service.applyProbe(text)
    }
  }

  Process {
    id: sharingProbe
    command: ["bash", "-c", service.sharingScript]
    onExited: function(exitCode) { service.sharing = exitCode === 0 }
  }

  Timer {
    running: service.armed && service.pauseWhenSharing
    interval: 5000
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sharingProbe.running) sharingProbe.running = true
  }

  function loadCatalog(raw) {
    var loaded = Actions.loadCatalog(raw)
    fileEntries = loaded.entries
    catalogErrors = loaded.errors
    installedPacks = loaded.packs
    for (var i = 0; i < loaded.errors.length; i++) console.warn("blip: " + loaded.errors[i])
  }

  // Queued, not dropped: the running scan may predate the change.
  property bool rescanQueued: false

  function rescan() {
    if (scan.running) {
      rescanQueued = true
      return
    }
    scan.command = ["bash", "-c", scanScript, service.pluginDir, service.userDir]
    scan.running = true
  }

  // Markers carry a random per-run token so file contents cannot forge them.
  readonly property string scanScript: ""
    + "shopt -s nullglob; "
    + "t=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \\n'); "
    + "printf '===blip-scan::%s===\\n' \"$t\"; "
    + "emit() { printf '===%s@%s::%s===\\n' \"$t\" \"$1\" \"$2\"; cat -- \"$2\"; printf '\\n===%s@EOF===\\n' \"$t\"; }; "
    + "scan() { local origin=$1 dir=$2; [[ -d $dir ]] || return 0; "
    + "  for file in \"$dir\"/*.jsonc \"$dir\"/*.json; do [[ -f $file ]] && emit \"$origin\" \"$file\"; done; }; "
    + "mkdir -p \"$1/actions\" \"$1/packs\"; "
    + "scan builtin \"$0/actions\"; "
    + "for pack in \"$1\"/packs/*/; do printf '===%s@packdir::%s===\\n' \"$t\" \"$pack\"; scan pack \"$pack/actions\"; done; "
    + "scan user \"$1/actions\""

  Process {
    id: scan
    stdout: StdioCollector {
      id: scanOut
      waitForEnd: true
      onStreamFinished: service.loadCatalog(text)
    }
    onExited: {
      catalogWatcher.running = true
      if (service.rescanQueued) {
        service.rescanQueued = false
        service.rescan()
      }
    }
  }

  Process {
    id: catalogWatcher
    command: ["inotifywait", "-m", "-r", "-q", "-e", "close_write,create,delete,move",
      "--format", "%w%f", service.userDir]
    stdout: SplitParser {
      onRead: function() { rescanDebounce.restart() }
    }
    onExited: if (service.pluginDir) catalogWatcherRestart.restart()
  }

  Timer {
    id: catalogWatcherRestart
    interval: 2000
    onTriggered: catalogWatcher.running = true
  }

  Timer {
    id: rescanDebounce
    interval: 200
    onTriggered: service.rescan()
  }

  onPluginDirChanged: if (pluginDir) rescan()

  FileView {
    id: consentFile
    path: service.userDir + "/consent.json"
    watchChanges: true
    printErrors: false
    onLoaded: service.applyConsent(text())
    onLoadFailed: service.applyConsent("")
    onFileChanged: reload()
  }

  function applyConsent(raw) {
    var next = ({})
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      var ids = Array.isArray(parsed.allowed) ? parsed.allowed : []
      for (var i = 0; i < ids.length; i++) next[String(ids[i])] = true
    } catch (e) {}
    consented = next
  }

  function grantConsent(id) {
    if (consented[id]) return
    var next = ({})
    var ids = []
    for (var key in consented) { next[key] = true; ids.push(key) }
    next[id] = true
    ids.push(id)
    consented = next
    consentFile.setText(JSON.stringify({ allowed: ids }, null, 2) + "\n")
  }

  function forgetConsent() {
    consented = ({})
    consentFile.setText(JSON.stringify({ allowed: [] }, null, 2) + "\n")
  }

  Popup {
    id: popup
    service: service

    onRunRequested: function(action) {
      if (action.network && !service.consented[action.id]) service.grantConsent(action.id)
      runner.run(action, popup.detection)
    }
    onCopyRequested: function(text) {
      runner.copyText(text)
      popup.flash("Copied")
    }
  }

  Runner {
    id: runner
    service: service

    onCompleted: function(action, payload) {
      if (!popup.busy) return
      if (!payload.ok) {
        popup.showResult({ title: "Failed", body: payload.body || "No output", tone: "urgent", render: "text" })
        return
      }
      switch (action.output) {
      case "show":
        if (!payload.body.length) { popup.flash("Nothing to show"); return }
        popup.showResult(payload)
        return
      case "copy":
        runner.copyText(payload.copy)
        popup.flash("Copied")
        return
      case "replace":
        runner.copyText(payload.copy)
        popup.close()
        runner.pasteBack()
        return
      }
      if (action.keepOpen) popup.busy = false
      else popup.close()
    }
  }

  // Unfocused, the popup cannot hear a key, so Hyprland holds them while it is up:
  // the letters the chips advertise are consumed, the rest pass through and dismiss.
  QtObject {
    id: passiveKeys

    readonly property var filler: [
      "a","b","c","d","e","f","g","h","i","j","k","l","m",
      "n","o","p","q","r","s","t","u","v","w","x","y","z",
      "0","1","2","3","4","5","6","7","8","9",
      "Return","Tab","BackSpace","space","Left","Right","Up","Down"
    ]

    property var bound: []
    // One missed character is the worst a collision can cost.
    property bool disarmed: false

    // A result binds no filler: a stray key must not wipe out what is being read.
    function keyPlan() {
      if (popup.mode === "result") return { consume: ["Return", "c"], filler: false }
      if (popup.mode === "confirm") return { consume: ["Return"], filler: false }

      var consume = []
      if (!disarmed) {
        var rows = popup.rows || []
        for (var i = 0; i < rows.length; i++) {
          var key = String(rows[i].accelerator || "").toLowerCase()
          if (key.length === 1) consume.push(key)
        }
        if (popup.answer) consume.push("equal")
        if (popup.hasOverflow) consume.push("Tab")
        consume.push("Left")
        consume.push("Right")
      }
      return { consume: consume, filler: true }
    }

    function apply() {
      // Keyboard-active popups hold real focus and read keys directly.
      if (!popup.opened || popup.keyboardActive) { clear(); return }

      var plan = keyPlan()
      var taken = ({})
      for (var i = 0; i < plan.consume.length; i++) taken[plan.consume[i]] = true

      // This re-runs on every mode change; without the unbinds the sets stack.
      var lua = []
      for (var d = 0; d < bound.length; d++) lua.push('hl.unbind("' + bound[d] + '")')

      var next = []
      // Escape also reaches the window, which clears the selection behind it.
      lua.push(bindLine("Escape", "omarchy-shell blip key escape", true))
      next.push("Escape")
      for (var j = 0; j < plan.consume.length; j++) {
        lua.push(bindLine(plan.consume[j], "omarchy-shell blip key " + plan.consume[j], false))
        next.push(plan.consume[j])
      }
      if (plan.filler) {
        for (var k = 0; k < filler.length; k++) {
          var key = filler[k]
          if (taken[key]) continue
          lua.push(bindLine(key, "omarchy-shell blip dismiss", true))
          next.push(key)
        }
      }

      dispatch(lua)
      bound = next
    }

    function bindLine(key, command, passThrough) {
      return 'hl.bind("' + key + '", hl.dsp.exec_cmd("' + command + '"), {non_consuming='
        + (passThrough ? "true" : "false") + '})'
    }

    function clear() {
      if (!bound.length) return
      var lua = []
      for (var i = 0; i < bound.length; i++) lua.push('hl.unbind("' + bound[i] + '")')
      bound = []
      dispatch(lua)
    }

    // Only what can be bound consuming: a leak there eats the key system wide.
    function sweep() {
      var lua = []
      var extra = ["equal", "Tab", "Return", "Left", "Right"]
      for (var i = 0; i < filler.length; i++) {
        if (filler[i].length !== 1) continue
        lua.push('hl.unbind("' + filler[i] + '")')
      }
      for (var j = 0; j < extra.length; j++) lua.push('hl.unbind("' + extra[j] + '")')
      dispatch(lua)
    }

    // hyprctl keyword is refused by the Lua config parser, so binds go through eval.
    function dispatch(lua) {
      if (!lua.length) return
      Quickshell.execDetached(["hyprctl", "eval", lua.join(" ")])
    }
  }

  Connections {
    target: popup
    function onOpenedChanged() {
      if (!popup.opened) passiveKeys.disarmed = false
      passiveKeys.apply()
    }
    function onKeyboardActiveChanged() { passiveKeys.apply() }
    function onModeChanged() { passiveKeys.apply() }
    function onExpandedChanged() { passiveKeys.apply() }
  }

  Component.onDestruction: passiveKeys.clear()

  IpcHandler {
    target: "blip"

    function ping(): string { return "ok" }

    function trigger(): string {
      if (popup.opened && !popup.keyboardActive) { popup.setKeyboard(true); return "focused" }
      if (popup.opened) { popup.close(); return "closed" }
      return service.present(service.selection, true)
    }

    function show(): string { return service.present(service.selection, true) }
    function hide(): string { popup.close(); return "ok" }

    // Routed here by the Hyprland binds the popup registers while it is up.
    function key(name: string): string {
      if (!popup.opened) return "closed"
      var value = String(name || "")
      if (value === "escape" || value === "Escape") { popup.back(); return "back" }
      if (value === "Return") return popup.pressReturn() ? "ran" : "ignored"
      if (value === "Tab") return popup.pressTab() ? "expanded" : "ignored"
      if (value === "Left") return popup.pressMove(-1) ? "moved" : "ignored"
      if (value === "Right") return popup.pressMove(1) ? "moved" : "ignored"
      if (value === "equal") return popup.pressAnswer() ? "copied" : "ignored"
      if (value === "c" && popup.mode === "result")
        return popup.copyResult() ? "copied" : "ignored"
      if (value.length === 1
          && (popup.activateByKey(value) || popup.activateByKey(value.toUpperCase())))
        return "ran"
      // Anything else was a real keystroke on its way to the focused window.
      passiveKeys.disarmed = true
      popup.close()
      return "dismissed"
    }

    function dismiss(): string { popup.close(); return "ok" }

    function arm(): string { service.setArmed(true); return "armed" }
    function disarm(): string { service.setArmed(false); return "disarmed" }
    function toggle(): string {
      var next = !service.armed
      service.setArmed(next)
      return next ? "armed" : "disarmed"
    }

    function state(): string {
      return JSON.stringify({
        armed: service.armed,
        automatic: service.automatic,
        sharing: service.sharing,
        open: popup.opened,
        keyboard: popup.keyboardActive,
        bound: passiveKeys.bound.length,
        cursor: [popup.cursorX, popup.cursorY],
        actions: service.catalog.length,
        active: service.activeCatalog.length,
        packs: service.packList.length,
        errors: service.catalogErrors
      })
    }

    function actions(): string {
      var list = []
      for (var i = 0; i < service.catalog.length; i++) {
        var action = service.catalog[i]
        var run = action.run.kind
        if (action.run.builtin) run += ":" + action.run.builtin
        else if (action.run.script) run += ":" + action.run.script
        else if (action.run.target) run += ":" + action.run.target + "." + action.run.method
        list.push({
          id: action.id,
          label: action.label,
          origin: action.origin,
          types: action.when.types,
          matches: action.when.matches,
          network: action.network,
          output: action.output,
          enabled: service.isActionEnabled(action.id),
          run: run
        })
      }
      return JSON.stringify(list, null, 2)
    }

    function enable(id: string): string { service.setActionEnabled(id, true); return "ok" }
    function disable(id: string): string { service.setActionEnabled(id, false); return "ok" }

    function set(key: string, value: string): string {
      var name = String(key)
      var defaults = service.manifest && Util.isPlainObject(service.manifest.barWidget)
        ? service.manifest.barWidget.defaults : null
      if (!defaults || defaults[name] === undefined) return "error: unknown setting '" + name + "'"
      var raw = String(value)
      var coerced
      if (raw === "true") coerced = true
      else if (raw === "false") coerced = false
      else if (raw !== "" && isFinite(Number(raw))) coerced = Number(raw)
      else coerced = raw
      service.persist(name, coerced)
      return "ok"
    }

    function get(key: string): string {
      return JSON.stringify(service.setting(String(key)))
    }

    function register(json: string): string {
      var parsed
      try {
        parsed = JSON.parse(json)
      } catch (e) {
        return "error: " + e
      }
      var list = Array.isArray(parsed) ? parsed : [parsed]
      var next = service.runtimeEntries.filter(function(entry) {
        for (var i = 0; i < list.length; i++) {
          if (list[i] && String(list[i].id) === entry.id) return false
        }
        return true
      })
      for (var j = 0; j < list.length; j++) {
        var result = Actions.normalizeAction(list[j], "pack", "ipc")
        if (result.error) return "error: " + result.error
        next.push(result.action)
      }
      service.runtimeEntries = next
      return "ok"
    }

    function unregister(id: string): string {
      var key = String(id)
      service.runtimeEntries = service.runtimeEntries.filter(function(entry) { return entry.id !== key })
      return "ok"
    }

    function reload(): string { service.rescan(); return "ok" }
    function forget(): string { service.forgetConsent(); return "ok" }

    // Packs: the same operations the panel's PACKS section runs.
    function packs(): string { return JSON.stringify(service.packList, null, 2) }
    function packAdd(source: string): string { return service.packAdd(source) }
    function packUpdate(name: string): string { return service.packUpdate(name) }
    function packRemove(name: string): string { return service.packRemove(name) }

    function detect(text: string): string {
      var detection = Detect.detect(text)
      detection.primaryLabel = Detect.label(detection.primary)
      var menu = Actions.build(service.activeCatalog, detection, {
        app: service.lastApp,
        allowNetwork: service.allowNetwork,
        limit: service.maxActions
      })
      return JSON.stringify({
        types: detection.types,
        primary: detection.primary,
        label: detection.primaryLabel,
        instant: Transforms.instant(detection, Date.now()),
        actions: menu.all.map(function(action) { return action.id })
      }, null, 2)
    }
  }
}
