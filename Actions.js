var ORIGIN_RANK = { builtin: 0, pack: 1, user: 2 }
var RUN_KINDS = ["builtin", "exec", "script", "ipc"]
var OUTPUTS = ["none", "copy", "replace", "show"]
var ACCELERATORS = "asdfghjklqwertyuiopzxcvbnm1234567890"

function trim(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function toList(value) {
  if (Array.isArray(value)) return value.map(trim).filter(function(entry) { return entry.length > 0 })
  var single = trim(value)
  return single.length ? [single] : []
}

function stripComments(source) {
  var text = String(source || "")
  var out = ""
  var i = 0
  var inString = false
  var inLine = false
  var inBlock = false
  while (i < text.length) {
    var c = text.charAt(i)
    var next = text.charAt(i + 1)
    if (inLine) {
      if (c === "\n") { inLine = false; out += c }
      i++
      continue
    }
    if (inBlock) {
      if (c === "*" && next === "/") { inBlock = false; i += 2; continue }
      if (c === "\n") out += c
      i++
      continue
    }
    if (inString) {
      out += c
      if (c === "\\") { out += next; i += 2; continue }
      if (c === "\"") inString = false
      i++
      continue
    }
    if (c === "\"") { inString = true; out += c; i++; continue }
    if (c === "/" && next === "/") { inLine = true; i += 2; continue }
    if (c === "/" && next === "*") { inBlock = true; i += 2; continue }
    out += c
    i++
  }
  return out.replace(/,(\s*[}\]])/g, "$1")
}

function parseJsonc(source) {
  return JSON.parse(stripComments(source))
}

function normalizeWhen(raw) {
  var when = isObject(raw) ? raw : {}
  var normalized = {
    types: toList(when.types),
    notTypes: toList(when.notTypes),
    apps: toList(when.app || when.apps),
    notApps: toList(when.notApp || when.notApps),
    matches: trim(when.matches),
    notMatches: trim(when.notMatches),
    minLength: Number(when.minLength) > 0 ? Math.floor(Number(when.minLength)) : 0,
    maxLength: Number(when.maxLength) > 0 ? Math.floor(Number(when.maxLength)) : 0
  }
  normalized.regex = compile(normalized.matches)
  normalized.notRegex = compile(normalized.notMatches)
  return normalized
}

function compile(pattern) {
  if (!pattern) return null
  try {
    return new RegExp(pattern)
  } catch (e) {
    return null
  }
}

function normalizeRun(raw) {
  if (!isObject(raw)) return null
  for (var i = 0; i < RUN_KINDS.length; i++) {
    var kind = RUN_KINDS[i]
    if (raw[kind] === undefined) continue
    if (kind === "exec") {
      var argv = Array.isArray(raw.exec) ? raw.exec.map(String) : []
      return argv.length ? { kind: "exec", argv: argv } : null
    }
    if (kind === "ipc") {
      if (!isObject(raw.ipc)) return null
      var target = trim(raw.ipc.target)
      var method = trim(raw.ipc.method)
      return (target && method) ? { kind: "ipc", target: target, method: method } : null
    }
    var name = trim(raw[kind])
    if (!name) return null
    if (kind === "script" && (name.charAt(0) === "/" || name.indexOf("..") !== -1)) return null
    var run = { kind: kind }
    run[kind] = name
    return run
  }
  return null
}

function normalizeAction(raw, origin, source) {
  if (!isObject(raw)) return { error: "action must be an object" }
  var id = trim(raw.id)
  if (!id) return { error: "action is missing an id" }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id)) return { error: "invalid action id '" + id + "'" }

  if (raw.disabled === true) {
    return { action: { id: id, disabled: true, origin: origin, source: source } }
  }

  var label = trim(raw.label)
  if (!label) return { error: "action '" + id + "' is missing a label" }
  var run = normalizeRun(raw.run)
  if (!run) return { error: "action '" + id + "' has no usable run" }

  var output = trim(raw.output).toLowerCase()
  if (OUTPUTS.indexOf(output) === -1) output = "none"

  return {
    action: {
      id: id,
      label: label,
      icon: trim(raw.icon),
      description: trim(raw.description),
      key: trim(raw.key).slice(0, 1).toLowerCase(),
      when: normalizeWhen(raw.when),
      run: run,
      output: output,
      render: trim(raw.render) === "qr" ? "qr" : "text",
      network: raw.network === true,
      host: trim(raw.host),
      confirm: raw.confirm === true,
      keepOpen: raw.keepOpen === true,
      priority: Number(raw.priority) || 0,
      disabled: false,
      origin: origin,
      source: source
    }
  }
}

function mergeCatalog(entries) {
  var byId = {}
  var order = []
  var decorated = entries.map(function(action, index) { return { action: action, index: index } })
  decorated.sort(function(a, b) {
    var rank = (ORIGIN_RANK[a.action.origin] || 0) - (ORIGIN_RANK[b.action.origin] || 0)
    return rank !== 0 ? rank : a.index - b.index
  })
  for (var i = 0; i < decorated.length; i++) {
    var action = decorated[i].action
    if (!byId[action.id]) order.push(action.id)
    byId[action.id] = action
  }
  var out = []
  for (var j = 0; j < order.length; j++) {
    var merged = byId[order[j]]
    if (!merged.disabled) out.push(merged)
  }
  return out
}

function parseScan(text) {
  var lines = String(text || "").split("\n")
  var files = []
  var packs = []
  var current = null

  var token = ""
  var start = 0
  var opener = (lines[0] || "").match(/^===blip-scan::([0-9a-f]+)===$/)
  if (opener) {
    token = opener[1]
    start = 1
  }
  var markerPrefix = "===" + token + "@"

  for (var i = start; i < lines.length; i++) {
    var line = lines[i]
    var origin = null
    var source = null
    var eof = false

    if (token) {
      if (line.indexOf(markerPrefix) === 0 && line.slice(-3) === "===") {
        var inner = line.slice(markerPrefix.length, -3)
        if (inner === "EOF") {
          eof = true
        } else {
          var sep = inner.indexOf("::")
          if (sep > 0) {
            origin = inner.slice(0, sep)
            source = inner.slice(sep + 2)
          }
        }
      }
    } else {
      var header = line.match(/^===([a-z]+)::(.+)===$/)
      if (header) {
        origin = header[1]
        source = header[2]
      } else if (line === "=== EOF ===") {
        eof = true
      }
    }

    if (eof) {
      if (current) files.push(current)
      current = null
      continue
    }
    if (origin) {
      // A packdir marker is a bare header with no body
      if (origin === "packdir") {
        var path = source.replace(/\/+$/, "")
        packs.push({ name: path.slice(path.lastIndexOf("/") + 1), path: path })
        current = null
      } else {
        current = { origin: origin, source: source, body: [] }
      }
      continue
    }
    if (current) current.body.push(line)
  }
  return { files: files, packs: packs }
}

function loadCatalog(scanText) {
  var scanned = parseScan(scanText)
  var entries = []
  var errors = []
  for (var i = 0; i < scanned.files.length; i++) {
    var file = scanned.files[i]
    var origin = ORIGIN_RANK[file.origin] === undefined ? "user" : file.origin
    var parsed
    try {
      parsed = parseJsonc(file.body.join("\n"))
    } catch (e) {
      errors.push(file.source + ": " + e)
      continue
    }
    var list = Array.isArray(parsed) ? parsed : (isObject(parsed) && Array.isArray(parsed.actions) ? parsed.actions : [parsed])
    for (var j = 0; j < list.length; j++) {
      var result = normalizeAction(list[j], origin, file.source)
      if (result.error) errors.push(file.source + ": " + result.error)
      else entries.push(result.action)
    }
  }
  return { entries: entries, errors: errors, packs: scanned.packs }
}

// ------------------------------------------------------------------ packs
// A pack is a git repository cloned under ~/.config/omarchy/blip/packs/.

function isPackSource(url) {
  var s = trim(url)
  if (/^https:\/\/\S+$/.test(s)) return true
  if (/^\/\S+$/.test(s)) return true // a local directory, for developing packs
  return false
}

function isPackName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(String(name || ""))
}

// "https://github.com/you/Blip-Pack-DevTools.git" -> "devtools".
// Lowercase before stripping, or a cased prefix survives and the same repo
// installs under two names depending on how the URL was typed.
function packNameFromSource(url) {
  var base = trim(url).replace(/\/+$/, "").replace(/\.git$/i, "")
  base = base.slice(base.lastIndexOf("/") + 1).toLowerCase()
  base = base.replace(/^blip-pack-/, "").replace(/^blip-/, "")
  base = base.replace(/[^a-z0-9._-]+/g, "-").replace(/^[-._]+|[-._]+$/g, "")
  return isPackName(base) ? base : ""
}

var MODULE_TITLES = { core: "Core", text: "Text tools" }

function titleize(name) {
  var cleaned = String(name === undefined || name === null ? "" : name)
    .replace(/[-_]+/g, " ").replace(/^\s+|\s+$/g, "")
  if (!cleaned.length) return ""
  return cleaned.charAt(0).toUpperCase() + cleaned.slice(1)
}

function moduleOf(action) {
  var source = String(action.source || "")
  if (action.origin === "user") return { key: "user", title: "Your actions" }
  if (action.origin === "pack") {
    var pack = source.match(/\/packs\/([^\/]+)\//)
    if (pack) return { key: "pack:" + pack[1], title: titleize(pack[1]) }
    return { key: "runtime", title: "From other plugins" }
  }
  var base = source.replace(/^.*\//, "").replace(/\.[^.]*$/, "")
  return { key: "builtin:" + base, title: MODULE_TITLES[base] || titleize(base) }
}

function groupCatalog(catalog) {
  var byKey = {}
  var order = []
  for (var i = 0; i < catalog.length; i++) {
    var mod = moduleOf(catalog[i])
    if (!byKey[mod.key]) {
      byKey[mod.key] = { key: mod.key, title: mod.title, actions: [] }
      order.push(mod.key)
    }
    byKey[mod.key].actions.push(catalog[i])
  }
  var out = []
  for (var j = 0; j < order.length; j++) out.push(byKey[order[j]])
  return out
}

function hasAny(list, values) {
  for (var i = 0; i < list.length; i++) if (values.indexOf(list[i]) !== -1) return true
  return false
}

function appMatches(patterns, app) {
  var haystack = String(app || "").toLowerCase()
  if (!haystack) return false
  for (var i = 0; i < patterns.length; i++) {
    if (haystack.indexOf(patterns[i].toLowerCase()) !== -1) return true
  }
  return false
}

function matches(action, detection, context) {
  var when = action.when
  var value = detection.value
  var ctx = context || {}

  if (when.minLength && value.length < when.minLength) return false
  if (when.maxLength && value.length > when.maxLength) return false
  if (when.types.length && when.types.indexOf("*") === -1 && !hasAny(when.types, detection.types)) return false
  if (when.notTypes.length && hasAny(when.notTypes, detection.types)) return false
  if (when.apps.length && !appMatches(when.apps, ctx.app)) return false
  if (when.notApps.length && appMatches(when.notApps, ctx.app)) return false
  if (when.matches && (!when.regex || !when.regex.test(value))) return false
  if (when.notMatches && when.notRegex && when.notRegex.test(value)) return false
  return true
}

function score(action, detection) {
  var best = 0
  for (var i = 0; i < action.when.types.length; i++) {
    var index = detection.types.indexOf(action.when.types[i])
    if (index === -1) continue
    var rank = detection.types.length - index
    if (rank > best) best = rank
  }
  if (action.when.matches.length) best = Math.max(best, detection.types.length + 1)
  return (best > 0 ? 10000 : 0) + best * 100 + action.priority
}

function assignKeys(actions) {
  var taken = {}
  var out = []
  var pending = []
  var i

  for (i = 0; i < actions.length; i++) {
    var action = actions[i]
    var copy = shallow(action)
    if (action.key && !taken[action.key]) {
      taken[action.key] = true
      copy.accelerator = action.key
      out.push(copy)
    } else {
      copy.accelerator = ""
      out.push(copy)
      pending.push(copy)
    }
  }

  for (i = 0; i < pending.length; i++) {
    var label = pending[i].label.toLowerCase()
    var chosen = ""
    for (var c = 0; c < label.length && !chosen; c++) {
      var letter = label.charAt(c)
      if (ACCELERATORS.indexOf(letter) !== -1 && !taken[letter]) chosen = letter
    }
    for (var f = 0; f < ACCELERATORS.length && !chosen; f++) {
      if (!taken[ACCELERATORS.charAt(f)]) chosen = ACCELERATORS.charAt(f)
    }
    if (chosen) {
      taken[chosen] = true
      pending[i].accelerator = chosen
    }
  }
  return out
}

function shallow(source) {
  var copy = {}
  for (var key in source) copy[key] = source[key]
  return copy
}

function build(catalog, detection, context) {
  var ctx = context || {}
  var limit = Number(ctx.limit) > 0 ? Math.floor(Number(ctx.limit)) : 6
  var eligible = []

  for (var i = 0; i < catalog.length; i++) {
    var action = catalog[i]
    if (action.network && !ctx.allowNetwork) continue
    if (!matches(action, detection, ctx)) continue
    eligible.push({ action: action, score: score(action, detection), order: i })
  }

  eligible.sort(function(a, b) {
    if (b.score !== a.score) return b.score - a.score
    return a.order - b.order
  })

  var ranked = assignKeys(eligible.map(function(entry) { return entry.action }))
  return {
    all: ranked,
    visible: ranked.slice(0, limit),
    overflow: ranked.slice(limit)
  }
}

function percentEncode(value) {
  return encodeURIComponent(String(value === undefined || value === null ? "" : value))
}

function variables(detection) {
  var path = detection.meta && detection.meta.path ? detection.meta.path : null
  return {
    text: detection.text,
    value: detection.value,
    enc: percentEncode(detection.value),
    url: (detection.meta && detection.meta.url) || detection.value,
    dir: path ? path.dir : "",
    base: path ? path.base : "",
    path: path ? path.path : "",
    line: path && path.line ? String(path.line) : "",
    type: detection.primary
  }
}

function expand(template, detection) {
  var vars = variables(detection)
  return String(template === undefined || template === null ? "" : template)
    .replace(/\$\{(\w+)\}/g, function(match, name) {
      return vars[name] === undefined ? match : String(vars[name])
    })
}

function expandArgv(argv, detection) {
  var out = []
  for (var i = 0; i < argv.length; i++) out.push(expand(argv[i], detection))
  return out
}

function hostOf(action, detection) {
  if (action.host) return action.host
  if (action.run.kind !== "exec") return ""
  var argv = expandArgv(action.run.argv, detection)
  for (var i = 0; i < argv.length; i++) {
    var match = argv[i].match(/^[a-z][a-z0-9+.-]*:\/\/([^\/\s:]+)/i)
    if (match) return match[1]
  }
  return ""
}
