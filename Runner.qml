import QtQuick
import Quickshell
import Quickshell.Io
import "Actions.js" as Actions
import "Transforms.js" as Transforms

Item {
  id: runner

  property var service: null
  property var action: null
  property var detection: null

  signal completed(var action, var payload)

  function run(nextAction, nextDetection) {
    action = nextAction
    detection = nextDetection

    switch (nextAction.run.kind) {
    case "builtin":
      finish(Transforms.run(nextAction.run.builtin, nextDetection, Date.now()))
      return
    case "exec":
      runExec(nextAction, nextDetection)
      return
    case "script":
      runScript(nextAction, nextDetection)
      return
    case "ipc":
      runIpc(nextAction, nextDetection)
      return
    }
    finish({ ok: false, body: "That action has nothing to run" })
  }

  function finish(payload) {
    var result = payload || {}
    var render = action && action.render ? action.render : "text"
    var copy = render === "qr" ? detection.text
      : (result.copy === undefined ? String(result.body || "") : String(result.copy))
    completed(action, {
      ok: result.ok !== false,
      title: String(result.title || ""),
      body: String(result.body || ""),
      copy: String(copy),
      tone: String(result.tone || ""),
      render: render,
      replace: render !== "qr" && !!action && action.output === "edit"
    })
  }

  function copyText(text) {
    clip.payload = String(text || "")
    clip.stdinEnabled = true
    clip.running = true
  }

  // One process, in order: the clipboard is claimed before the chord fires,
  // and the text reaches wl-copy on stdin, never through the process table.
  // The sleep is for focus, and the chord only fires if the window that owned
  // the selection has it back — anywhere else, the paste stays a copy.
  function replaceText(text) {
    paste.payload = String(text || "")
    paste.command = ["bash", "-c",
      'wl-copy && sleep 0.2'
      + ' && { [ -z "$0" ] || [ "$(hyprctl -j activewindow | jq -r .address)" = "$0" ]; }'
      + ' && exec "$@"',
      service ? String(service.lastWindow || "") : ""]
      .concat(Actions.pasteChord(service ? service.lastApp : ""))
    paste.stdinEnabled = true
    paste.running = true
  }

  function scriptPath(action) {
    var source = String(action.source || "")
    var actionsDir = source.slice(0, source.lastIndexOf("/"))
    var base = actionsDir.slice(0, actionsDir.lastIndexOf("/"))
    return base + "/scripts/" + action.run.script
  }

  function contextEnvironment(action, detection) {
    return {
      BLIP_TYPE: String(detection.primary || ""),
      BLIP_TYPES: detection.types.join(" "),
      BLIP_APP: service ? String(service.lastApp || "") : "",
      BLIP_ACTION: String(action.id || "")
    }
  }

  function start(command, input, action, detection) {
    capture.command = command
    capture.environment = contextEnvironment(action, detection)
    capture.input = input === null || input === undefined ? "" : String(input)
    capture.wantsInput = input !== null && input !== undefined
    capture.stdinEnabled = capture.wantsInput
    capture.running = true
  }

  function runExec(action, detection) {
    var argv = Actions.expandArgv(action.run.argv, detection)
    if (action.output === "none") {
      Quickshell.execDetached(argv)
      finish({ ok: true })
      return
    }
    start(argv, null, action, detection)
  }

  function runScript(action, detection) {
    start(["bash", scriptPath(action)], detection.text, action, detection)
  }

  function runIpc(action, detection) {
    start(["omarchy-shell", action.run.target, action.run.method, detection.text], null, action, detection)
  }

  function collected(exitCode) {
    var out = captureOut.text || ""
    var err = (captureErr.text || "").replace(/^\s+|\s+$/g, "")
    if (exitCode !== 0) {
      finish({ ok: false, body: err || ("Exited with status " + exitCode) })
      return
    }
    finish({ ok: true, body: out.replace(/\n+$/, ""), tone: "" })
  }

  Process {
    id: capture

    property string input: ""
    property bool wantsInput: false

    onStarted: {
      if (!wantsInput) return
      write(input)
      stdinEnabled = false
      input = ""
    }
    onExited: function(exitCode) { runner.collected(exitCode) }

    stdout: StdioCollector { id: captureOut; waitForEnd: true }
    stderr: StdioCollector { id: captureErr; waitForEnd: true }
  }

  Timer {
    running: capture.running
    interval: 20000
    onTriggered: {
      capture.running = false
      runner.finish({ ok: false, body: "Timed out after 20 seconds" })
    }
  }

  function feed(proc) {
    proc.write(proc.payload)
    proc.stdinEnabled = false
    proc.payload = ""
  }

  Process {
    id: clip

    property string payload: ""

    command: ["wl-copy"]
    onStarted: runner.feed(clip)
  }

  Process {
    id: paste

    property string payload: ""

    onStarted: runner.feed(paste)
    stderr: StdioCollector { id: pasteErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("blip: replace did not paste; the result is on the clipboard "
          + String(pasteErr.text || "").trim())
    }
  }
}
