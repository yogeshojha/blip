import QtQuick
import Quickshell
import Quickshell.Io

// Omarchy 4.0.3 stopped handing third-party plugins `shell.shellConfig`,
// so without this every setting fell back to its default

Item {
  id: root
  property string pluginId: "io.github.yogeshojha.blip"
  property string path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  property var entry: ({})
  property bool loaded: false
  readonly property var config: ({ plugins: [entry] })

  function reload() { settingsFile.reload() }

  function remember(next) {
    var copy = {}
    for (var k in next) if (k !== "id") copy[k] = next[k]
    copy.id = root.pluginId
    root.entry = copy
  }

  // Blip is a bar widget, so Omarchy's updateEntryInline() persists its entry
  // inside bar.layout.<section>, falling back to the top-level plugins array
  // only when the id isn't found there (see shell.qml). This mirrors that
  // same lookup order, or every read misses the entry and finds only {}.
  function findEntry(parsed) {
    var sections = ["left", "center", "right"]
    var layout = parsed && parsed.bar ? parsed.bar.layout : null
    for (var s = 0; s < sections.length; s++) {
      var list = layout ? layout[sections[s]] : null
      if (!Array.isArray(list)) continue
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].id || "") === root.pluginId) return list[i]
      }
    }
    var plugins = parsed && Array.isArray(parsed.plugins) ? parsed.plugins : []
    for (var j = 0; j < plugins.length; j++) {
      if (plugins[j] && String(plugins[j].id || "") === root.pluginId) return plugins[j]
    }
    return {}
  }

  function parse() {
    var raw = ""
    try { raw = String(settingsFile.text() || "") } catch (e) { raw = "" }
    if (raw.trim().length === 0) {
      root.entry = {}
      root.loaded = true
      return
    }
    try {
      root.entry = findEntry(JSON.parse(raw))
      root.loaded = true
    } catch (e) {
      console.warn("cannot read saved plugin settings: " + e)
    }
  }

  FileView {
    id: settingsFile
    path: root.path
    blockLoading: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse()
    onLoadFailed: root.parse()
  }

  Component.onCompleted: parse()
}
