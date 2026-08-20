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
      render: render
    })
  }

  function copyText(text) {
    clip.payload = String(text || "")
    clip.stdinEnabled = true
    clip.running = true
  }

  function pasteBack() {
    Quickshell.execDetached(["bash", "-c", "sleep 0.2; wtype -M shift -k Insert -m shift"])
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

  Process {
    id: clip

    property string payload: ""

    command: ["wl-copy"]
    onStarted: {
      write(payload)
      stdinEnabled = false
      payload = ""
    }
  }
}
