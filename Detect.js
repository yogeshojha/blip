var TAGS = [
  "url", "email", "ip", "uuid", "jwt", "json", "hash", "color", "epoch",
  "number", "hex", "base64", "urlencoded", "path", "error", "code",
  "multiline", "word", "text"
]

var WEIGHT = {
  jwt: 100, json: 90, url: 85, uuid: 80, epoch: 78, color: 76, hash: 74,
  email: 72, ip: 70, path: 66, base64: 60, urlencoded: 58, hex: 55,
  error: 50, number: 40, code: 30, multiline: 10, word: 5, text: 0
}

var LABEL = {
  url: "URL", email: "Email", ip: "IP", uuid: "UUID", jwt: "JWT", json: "JSON",
  hash: "Hash", color: "Colour", epoch: "Timestamp", number: "Number",
  hex: "Hex", base64: "Base64", urlencoded: "Encoded", path: "Path",
  error: "Error", code: "Code", multiline: "Text", word: "Word", text: "Text"
}

var RE = {
  url: /^(?:https?|ftp|magnet):\/\/[^\s<>"]+$/i,
  bareUrl: /^www\.[^\s<>"]+\.[a-z]{2,}(?:[\/?#][^\s<>"]*)?$/i,
  email: /^[^\s@,;<>()]+@[^\s@,;<>()]+\.[A-Za-z]{2,}$/,
  ipv4: /^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\/\d{1,2})?(?::\d{1,5})?$/,
  ipv6: /^(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?:\/\d{1,3})?$/,
  uuid: /^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$/,
  jwt: /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$/,
  color: /^(?:#(?:[0-9A-Fa-f]{3,4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})|(?:rgba?|hsla?)\([^)]*\))$/,
  digits: /^\d+$/,
  number: /^[+-]?(?:\d+(?:[._]\d+)*|\d*\.\d+)(?:[eE][+-]?\d+)?$/,
  hex: /^(?:0x)?[0-9A-Fa-f]+$/,
  base64: /^[A-Za-z0-9+/]+={0,2}$/,
  base64url: /^[A-Za-z0-9_-]+={0,2}$/,
  percent: /%[0-9A-Fa-f]{2}/,
  absPath: /^(?:~|\.{1,2})?\/[^\0]*$/,
  filePath: /^file:\/\/\/[^\s]*$/,
  pathish: /^[\w.@+-]+(?:\/[\w.@ +-]+)+\/?$/,
  lineRef: /:(\d+)(?::(\d+))?$/,
  error: /(?:\b(?:error|exception|fatal|panic)\s*[:!]|\btraceback\b|\bsegfault\b|assertionerror|referenceerror|typeerror|syntaxerror|nullpointerexception|command not found|no such file or directory|permission denied|connection refused|cannot find module|undefined reference)/i,
  codeKeyword: /(?:^|\n)\s*(?:function|const|let|var|class|def|import|from|package|public|private|return|if|for|while|SELECT|INSERT|UPDATE|DELETE)\b/m,
  codePunct: /[{}();=<>]/,
  codeEnd: /[{};]\s*$/m,
  word: /^[\w'-]+$/
}

var MIN_EPOCH = 100000000        // 1973
var MAX_EPOCH = 4102444800       // 2100

function trim(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function decodeBase64(value) {
  var text = String(value === undefined || value === null ? "" : value)
    .replace(/-/g, "+").replace(/_/g, "/").replace(/\s/g, "")
  if (!text.length) return null
  var out = ""
  for (var i = 0; i < text.length; i += 4) {
    var bits = 0
    var count = 0
    for (var j = 0; j < 4; j++) {
      var ch = text.charAt(i + j)
      if (ch === "" || ch === "=") { bits = bits << 6; continue }
      var index = B64.indexOf(ch)
      if (index < 0) return null
      bits = (bits << 6) | index
      count++
    }
    if (count < 2) break
    out += String.fromCharCode((bits >> 16) & 0xff)
    if (count > 2) out += String.fromCharCode((bits >> 8) & 0xff)
    if (count > 3) out += String.fromCharCode(bits & 0xff)
  }
  return out
}

function printableRatio(value) {
  if (!value || !value.length) return 0
  var printable = 0
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code === 9 || code === 10 || code === 13 || (code >= 32 && code < 127) || code > 159) printable++
  }
  return printable / value.length
}

function parseJson(value) {
  var first = value.charAt(0)
  if (first !== "{" && first !== "[") return null
  try {
    var parsed = JSON.parse(value)
    return (parsed !== null && typeof parsed === "object") ? parsed : null
  } catch (e) {
    return null
  }
}

function parseJwt(value) {
  if (!RE.jwt.test(value)) return null
  var parts = value.split(".")
  if (parts[0].length < 4 || parts[1].length < 4) return null
  var headerRaw = decodeBase64(parts[0])
  var payloadRaw = decodeBase64(parts[1])
  if (!headerRaw || !payloadRaw) return null
  try {
    var header = JSON.parse(headerRaw)
    var payload = JSON.parse(payloadRaw)
    if (!header || typeof header !== "object" || !header.alg) return null
    if (!payload || typeof payload !== "object") return null
    return { header: header, payload: payload, signature: parts[2] }
  } catch (e) {
    return null
  }
}

function looksBase64(value) {
  if (value.length < 8 || value.length % 4 !== 0) return false
  if (!RE.base64.test(value) && !RE.base64url.test(value)) return false
  if (RE.digits.test(value)) return false
  if (/^[a-z]+$/.test(value) || /^[A-Z]+$/.test(value)) return false
  var decoded = decodeBase64(value)
  return !!decoded && decoded.length > 0 && printableRatio(decoded) > 0.85
}

function looksIpv6(value) {
  var body = value.replace(/\/\d{1,3}$/, "")
  if (body.indexOf("::") !== -1) return true
  return body.split(":").length === 8
}

function looksCode(value) {
  if (RE.codeEnd.test(value)) return true
  return RE.codeKeyword.test(value) && RE.codePunct.test(value)
}

function looksHexBlob(value) {
  var body = value.replace(/^0x/i, "")
  if (body.length < 8 || body.length % 2 !== 0) return false
  if (!RE.hex.test(body)) return false
  return /[A-Fa-f]/.test(body) || /^0x/i.test(value)
}

function hashKind(value) {
  var body = value.replace(/^0x/i, "")
  if (!/^[0-9A-Fa-f]+$/.test(body)) return ""
  if (body.length === 32) return "MD5"
  if (body.length === 40) return "SHA-1"
  if (body.length === 64) return "SHA-256"
  if (body.length === 128) return "SHA-512"
  return ""
}

function epochValue(value) {
  if (!RE.digits.test(value)) return null
  var seconds
  if (value.length === 10) seconds = Number(value)
  else if (value.length === 13) seconds = Number(value) / 1000
  else return null
  if (!isFinite(seconds) || seconds < MIN_EPOCH || seconds > MAX_EPOCH) return null
  return { seconds: seconds, milliseconds: value.length === 13 }
}

function pathParts(value) {
  var cleaned = value.replace(/^file:\/\//, "")
  var lineMatch = cleaned.match(RE.lineRef)
  var line = 0
  if (lineMatch) {
    line = Number(lineMatch[1])
    cleaned = cleaned.slice(0, cleaned.length - lineMatch[0].length)
  }
  var slash = cleaned.lastIndexOf("/")
  return {
    path: cleaned,
    dir: slash > 0 ? cleaned.slice(0, slash) : (slash === 0 ? "/" : "."),
    base: slash >= 0 ? cleaned.slice(slash + 1) : cleaned,
    line: line
  }
}

function looksPath(value) {
  if (value.indexOf("\n") !== -1 || value.length > 4096) return false
  if (RE.filePath.test(value)) return true
  var withoutLine = value.replace(RE.lineRef, "")
  if (RE.absPath.test(withoutLine)) return true
  if (!RE.pathish.test(withoutLine) || withoutLine.indexOf("/") <= 0) return false
  if (withoutLine.indexOf(" ") !== -1) return false
  var segments = withoutLine.replace(/\/$/, "").split("/")
  if (segments.length < 2) return false
  var allNumeric = true
  for (var i = 0; i < segments.length; i++) {
    if (!RE.digits.test(segments[i])) { allNumeric = false; break }
  }
  if (allNumeric) return false
  if (withoutLine.length !== value.length) return true
  if (segments.length >= 3) return true
  return /\.[A-Za-z0-9]{1,8}$/.test(withoutLine)
}

function detect(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw)
  var value = trim(text)
  var found = {}
  var meta = {}

  if (!value.length) return { text: text, value: "", types: [], primary: "", meta: meta }

  var multiline = value.indexOf("\n") !== -1
  var singleLine = !multiline

  if (singleLine) {
    if (RE.url.test(value)) found.url = true
    else if (RE.bareUrl.test(value)) { found.url = true; meta.url = "https://" + value }
    if (RE.email.test(value)) found.email = true
    if (RE.ipv4.test(value) || (value.indexOf(":") !== -1 && RE.ipv6.test(value) && looksIpv6(value))) found.ip = true
    if (RE.uuid.test(value)) found.uuid = true
    if (RE.color.test(value)) found.color = true
    if (RE.word.test(value)) found.word = true
  }

  var jwt = singleLine ? parseJwt(value) : null
  if (jwt) { found.jwt = true; meta.jwt = jwt }

  var json = parseJson(value)
  if (json) { found.json = true; meta.json = json }

  if (singleLine && !found.url && !found.uuid) {
    var epoch = epochValue(value)
    if (epoch) { found.epoch = true; meta.epoch = epoch }
    if (RE.number.test(value)) found.number = true
    if (looksHexBlob(value)) {
      found.hex = true
      var kind = hashKind(value)
      if (kind) { found.hash = true; meta.hash = kind }
    }
    if (!found.jwt && !found.hex && looksBase64(value)) found.base64 = true
  }

  if (RE.percent.test(value)) {
    try {
      if (decodeURIComponent(value.replace(/\+/g, " ")) !== value) found.urlencoded = true
    } catch (e) {}
  }

  if (!found.url && !found.email && looksPath(value)) {
    found.path = true
    meta.path = pathParts(value)
  }

  if (RE.error.test(value)) found.error = true
  if (!found.json && !found.jwt && looksCode(value)) found.code = true
  if (multiline) found.multiline = true
  found.text = true

  var types = []
  for (var i = 0; i < TAGS.length; i++) if (found[TAGS[i]]) types.push(TAGS[i])
  types.sort(function(a, b) { return (WEIGHT[b] || 0) - (WEIGHT[a] || 0) })

  return {
    text: text,
    value: value,
    types: types,
    primary: types.length ? types[0] : "text",
    meta: meta
  }
}

function label(type) {
  return LABEL[type] || String(type || "")
}
