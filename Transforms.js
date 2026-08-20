var SECOND = 1000
var MINUTE = 60 * SECOND
var HOUR = 60 * MINUTE
var DAY = 24 * HOUR

function ok(title, body, copy, tone) {
  return { ok: true, title: title, body: body, copy: copy === undefined ? body : copy, tone: tone || "" }
}

function fail(message) {
  return { ok: false, title: "", body: message, copy: "", tone: "urgent" }
}

function pad(value, width) {
  var text = String(value)
  while (text.length < width) text = "0" + text
  return text
}

function formatDate(date) {
  return pad(date.getFullYear(), 4) + "-" + pad(date.getMonth() + 1, 2) + "-" + pad(date.getDate(), 2)
    + " " + pad(date.getHours(), 2) + ":" + pad(date.getMinutes(), 2) + ":" + pad(date.getSeconds(), 2)
}

function formatUtc(date) {
  return pad(date.getUTCFullYear(), 4) + "-" + pad(date.getUTCMonth() + 1, 2) + "-" + pad(date.getUTCDate(), 2)
    + " " + pad(date.getUTCHours(), 2) + ":" + pad(date.getUTCMinutes(), 2) + ":" + pad(date.getUTCSeconds(), 2)
}

function plural(count, unit) {
  return count + " " + unit + (count === 1 ? "" : "s")
}

function relative(deltaMs) {
  var ahead = deltaMs > 0
  var span = Math.abs(deltaMs)
  var phrase
  if (span < MINUTE) phrase = plural(Math.round(span / SECOND), "second")
  else if (span < HOUR) phrase = plural(Math.round(span / MINUTE), "minute")
  else if (span < DAY) phrase = plural(Math.round(span / HOUR), "hour")
  else if (span < 60 * DAY) phrase = plural(Math.round(span / DAY), "day")
  else if (span < 730 * DAY) phrase = plural(Math.round(span / (30.44 * DAY)), "month")
  else phrase = plural(Math.round(span / (365.25 * DAY)), "year")
  return ahead ? "in " + phrase : phrase + " ago"
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

function encodeBase64(value) {
  var text = String(value === undefined || value === null ? "" : value)
  var out = ""
  for (var i = 0; i < text.length; i += 3) {
    var has1 = i + 1 < text.length
    var has2 = i + 2 < text.length
    var b0 = text.charCodeAt(i) & 0xff
    var b1 = has1 ? text.charCodeAt(i + 1) & 0xff : 0
    var b2 = has2 ? text.charCodeAt(i + 2) & 0xff : 0
    var bits = (b0 << 16) | (b1 << 8) | b2
    out += B64.charAt((bits >> 18) & 63) + B64.charAt((bits >> 12) & 63)
    out += has1 ? B64.charAt((bits >> 6) & 63) : "="
    out += has2 ? B64.charAt(bits & 63) : "="
  }
  return out
}

function utf8(raw) {
  if (raw === null || raw === undefined) return null
  var escaped = ""
  for (var i = 0; i < raw.length; i++) {
    var byte = raw.charCodeAt(i) & 0xff
    escaped += "%" + (byte < 16 ? "0" : "") + byte.toString(16)
  }
  try {
    return decodeURIComponent(escaped)
  } catch (e) {
    return raw
  }
}

function latin1(value) {
  var encoded = encodeURIComponent(String(value === undefined || value === null ? "" : value))
  var out = ""
  for (var i = 0; i < encoded.length; i++) {
    if (encoded.charAt(i) !== "%") { out += encoded.charAt(i); continue }
    out += String.fromCharCode(parseInt(encoded.substr(i + 1, 2), 16))
    i += 2
  }
  return out
}

function words(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .split(/[^A-Za-z0-9]+/)
    .filter(function(part) { return part.length > 0 })
}

function titleCase(value) {
  return String(value || "").replace(/\w\S*/g, function(part) {
    return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase()
  })
}

function camelCase(value) {
  var parts = words(value)
  if (!parts.length) return ""
  return parts[0].toLowerCase() + parts.slice(1).map(function(part) {
    return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase()
  }).join("")
}

function jwtClaimLines(payload, now) {
  var lines = []
  var stamps = [
    { key: "iat", label: "issued" },
    { key: "nbf", label: "valid from" },
    { key: "exp", label: "expires" }
  ]
  for (var i = 0; i < stamps.length; i++) {
    var raw = payload[stamps[i].key]
    if (typeof raw !== "number") continue
    var when = new Date(raw * 1000)
    var suffix = stamps[i].key === "iat" ? "" : "  (" + relative(raw * 1000 - now) + ")"
    lines.push(pad(stamps[i].key, 3) + "  " + stamps[i].label + " " + formatDate(when) + suffix)
  }
  return lines
}

function jwtDecode(detection, now) {
  var jwt = detection.meta ? detection.meta.jwt : null
  if (!jwt) return fail("That is not a JSON Web Token")

  var expired = typeof jwt.payload.exp === "number" && jwt.payload.exp * 1000 < now
  var notYet = typeof jwt.payload.nbf === "number" && jwt.payload.nbf * 1000 > now
  var body = JSON.stringify(jwt.payload, null, 2)
  var claims = jwtClaimLines(jwt.payload, now)
  var header = "alg " + jwt.header.alg + (jwt.header.typ ? "   typ " + jwt.header.typ : "")
  var status = expired ? "EXPIRED" : (notYet ? "NOT YET VALID" : "")

  return {
    ok: true,
    title: "JWT payload" + (status ? " · " + status : ""),
    body: header + "\n\n" + body + (claims.length ? "\n\n" + claims.join("\n") : ""),
    copy: body,
    tone: expired || notYet ? "urgent" : ""
  }
}

function epochLocal(detection, now) {
  var epoch = detection.meta ? detection.meta.epoch : null
  if (!epoch) return fail("That is not a Unix timestamp")
  var ms = epoch.seconds * 1000
  var when = new Date(ms)
  var local = formatDate(when)
  return ok(
    "Unix " + (epoch.milliseconds ? "milliseconds" : "seconds"),
    local + "\n" + formatUtc(when) + " UTC\n" + relative(ms - now),
    local
  )
}

function jsonFormat(detection, minify) {
  var json = detection.meta ? detection.meta.json : null
  if (json === null || json === undefined) return fail("That is not JSON")
  var text = minify ? JSON.stringify(json) : JSON.stringify(json, null, 2)
  return ok(minify ? "Minified" : "Formatted", text)
}

function count(detection) {
  var text = String(detection.text || "")
  var trimmed = text.replace(/^\s+|\s+$/g, "")
  var wordCount = trimmed.length ? trimmed.split(/\s+/).length : 0
  return ok("Count", text.length + " characters\n" + wordCount + " words\n" + (text.length ? text.split("\n").length : 0) + " lines", String(text.length))
}

function run(name, detection, now) {
  var when = now === undefined ? Date.now() : now
  var value = detection.value
  var decoded

  switch (String(name || "")) {
  case "copy":
    return ok("Copied", detection.text)
  case "json.format":
    return jsonFormat(detection, false)
  case "json.minify":
    return jsonFormat(detection, true)
  case "jwt.decode":
    return jwtDecode(detection, when)
  case "epoch.local":
    return epochLocal(detection, when)
  case "base64.decode":
    decoded = utf8(decodeBase64(value))
    return decoded === null ? fail("That is not valid base64") : ok("Decoded", decoded)
  case "base64.encode":
    decoded = encodeBase64(latin1(detection.text))
    return decoded === null ? fail("Could not encode that") : ok("Encoded", decoded)
  case "hex.decode":
    return hexDecode(value)
  case "url.decode":
    try {
      return ok("Decoded", decodeURIComponent(value.replace(/\+/g, " ")))
    } catch (e) {
      return fail("That is not valid percent-encoding")
    }
  case "url.encode":
    return ok("Encoded", encodeURIComponent(detection.text))
  case "case.upper":
    return ok("Upper case", detection.text.toUpperCase())
  case "case.lower":
    return ok("Lower case", detection.text.toLowerCase())
  case "case.title":
    return ok("Title case", titleCase(detection.text))
  case "case.snake":
    return ok("snake_case", words(detection.text).join("_").toLowerCase())
  case "case.kebab":
    return ok("kebab-case", words(detection.text).join("-").toLowerCase())
  case "case.camel":
    return ok("camelCase", camelCase(detection.text))
  case "count":
    return count(detection)
  }
  return fail("Unknown built-in '" + name + "'")
}

function hexDecode(value) {
  var body = String(value || "").replace(/^0x/i, "").replace(/[\s:]/g, "")
  if (!body.length || body.length % 2 !== 0 || !/^[0-9A-Fa-f]+$/.test(body)) return fail("That is not hex")
  var out = ""
  for (var i = 0; i < body.length; i += 2) out += String.fromCharCode(parseInt(body.substr(i, 2), 16))
  var text = utf8(out)
  return ok("Decoded", text === null ? out : text)
}

function formatNumber(value) {
  if (!isFinite(value)) return null
  var rounded = Math.round(value * 1e10) / 1e10
  return String(rounded)
}

function evalMath(source) {
  var text = String(source || "").replace(/\s+/g, "")
    .replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/,/g, "")
  if (!text.length || text.length > 200) return null
  if (/[^0-9+\-*/%^().]/.test(text)) return null
  if (!/[+*/%^(]/.test(text)) return null
  if (!/\d/.test(text)) return null

  var pos = 0
  var failed = false

  function peek() { return text.charAt(pos) }

  function number() {
    var start = pos
    while (/[0-9.]/.test(peek())) pos++
    var chunk = text.slice(start, pos)
    if (!chunk.length || chunk === "." || chunk.indexOf(".") !== chunk.lastIndexOf(".")) { failed = true; return 0 }
    return parseFloat(chunk)
  }

  function primary() {
    if (peek() === "(") {
      pos++
      var inner = expr()
      if (peek() !== ")") { failed = true; return 0 }
      pos++
      return inner
    }
    return number()
  }

  function power() {
    var base = primary()
    if (peek() !== "^") return base
    pos++
    return Math.pow(base, factor())
  }

  function factor() {
    if (peek() === "-") { pos++; return -factor() }
    if (peek() === "+") { pos++; return factor() }
    return power()
  }

  function term() {
    var left = factor()
    while (!failed) {
      var op = peek()
      if (op === "*") { pos++; left = left * factor() }
      else if (op === "/") { pos++; left = left / factor() }
      else if (op === "%") { pos++; left = left % factor() }
      else break
    }
    return left
  }

  function expr() {
    var left = term()
    while (!failed) {
      var op = peek()
      if (op === "+") { pos++; left = left + term() }
      else if (op === "-") { pos++; left = left - term() }
      else break
    }
    return left
  }

  var result = expr()
  if (failed || pos !== text.length) return null
  return formatNumber(result)
}

var UNIT_TABLE = {
  mi: { to: "km", factor: 1.609344 },
  km: { to: "mi", factor: 1 / 1.609344 },
  ft: { to: "m", factor: 0.3048 },
  m: { to: "ft", factor: 1 / 0.3048 },
  yd: { to: "m", factor: 0.9144 },
  "in": { to: "cm", factor: 2.54 },
  cm: { to: "in", factor: 1 / 2.54 },
  lb: { to: "kg", factor: 0.45359237 },
  lbs: { to: "kg", factor: 0.45359237 },
  kg: { to: "lb", factor: 1 / 0.45359237 },
  oz: { to: "g", factor: 28.349523125 },
  g: { to: "oz", factor: 1 / 28.349523125 },
  gal: { to: "l", factor: 3.785411784 },
  l: { to: "gal", factor: 1 / 3.785411784 },
  mph: { to: "km/h", factor: 1.609344 },
  "km/h": { to: "mph", factor: 1 / 1.609344 },
  kmh: { to: "mph", factor: 1 / 1.609344 }
}

function round2(value) {
  return Math.round(value * 100) / 100
}

function unitInstant(value) {
  var match = String(value || "").match(/^(-?\d+(?:\.\d+)?)\s*(°?[a-zA-Z][a-zA-Z/]{0,10})\.?$/)
  if (!match) return null
  var amount = parseFloat(match[1])
  if (!isFinite(amount)) return null
  var unit = match[2].toLowerCase()

  if (unit === "f" || unit === "°f" || unit === "fahrenheit")
    return { text: "→ " + round2((amount - 32) * 5 / 9) + " °C", copy: round2((amount - 32) * 5 / 9) + " °C" }
  if (unit === "c" || unit === "°c" || unit === "celsius")
    return { text: "→ " + round2(amount * 9 / 5 + 32) + " °F", copy: round2(amount * 9 / 5 + 32) + " °F" }

  var entry = UNIT_TABLE[unit]
  if (!entry) return null
  var answer = round2(amount * entry.factor) + " " + entry.to
  return { text: "→ " + answer, copy: answer }
}

function clampByte(value) {
  return Math.max(0, Math.min(255, Math.round(value)))
}

function hexPair(value) {
  var text = clampByte(value).toString(16)
  return text.length < 2 ? "0" + text : text
}

function hueToChannel(p, q, t) {
  if (t < 0) t += 1
  if (t > 1) t -= 1
  if (t < 1 / 6) return p + (q - p) * 6 * t
  if (t < 1 / 2) return q
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
  return p
}

function colorInstant(value) {
  var text = String(value || "")

  var hex = text.match(/^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/)
  if (hex) {
    var body = hex[1]
    if (body.length <= 4) body = body.split("").map(function(ch) { return ch + ch }).join("")
    var r = parseInt(body.substr(0, 2), 16)
    var g = parseInt(body.substr(2, 2), 16)
    var b = parseInt(body.substr(4, 2), 16)
    var answer
    if (body.length === 8) {
      var alpha = Math.round(parseInt(body.substr(6, 2), 16) / 255 * 100) / 100
      answer = "rgba(" + r + ", " + g + ", " + b + ", " + alpha + ")"
    } else {
      answer = "rgb(" + r + ", " + g + ", " + b + ")"
    }
    return { text: "→ " + answer, copy: answer }
  }

  var rgb = text.match(/^rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*(?:[,/]\s*([\d.]+%?)\s*)?\)$/i)
  if (rgb) {
    var out = "#" + hexPair(Number(rgb[1])) + hexPair(Number(rgb[2])) + hexPair(Number(rgb[3]))
    if (rgb[4] !== undefined) {
      var a = rgb[4].charAt(rgb[4].length - 1) === "%" ? parseFloat(rgb[4]) / 100 : parseFloat(rgb[4])
      if (isFinite(a) && a < 1) out += hexPair(a * 255)
    }
    return { text: "→ " + out, copy: out }
  }

  var hsl = text.match(/^hsla?\(\s*([\d.]+)(?:deg)?\s*[, ]\s*([\d.]+)%\s*[, ]\s*([\d.]+)%\s*(?:[,/]\s*[\d.]+%?\s*)?\)$/i)
  if (hsl) {
    var h = (parseFloat(hsl[1]) % 360) / 360
    var s = Math.max(0, Math.min(1, parseFloat(hsl[2]) / 100))
    var l = Math.max(0, Math.min(1, parseFloat(hsl[3]) / 100))
    var rr, gg, bb
    if (s === 0) {
      rr = gg = bb = l
    } else {
      var q = l < 0.5 ? l * (1 + s) : l + s - l * s
      var p = 2 * l - q
      rr = hueToChannel(p, q, h + 1 / 3)
      gg = hueToChannel(p, q, h)
      bb = hueToChannel(p, q, h - 1 / 3)
    }
    var hexOut = "#" + hexPair(rr * 255) + hexPair(gg * 255) + hexPair(bb * 255)
    return { text: "→ " + hexOut, copy: hexOut }
  }

  return null
}

function instant(detection, now) {
  if (!detection || !detection.value) return null
  var when = now === undefined ? Date.now() : now

  if (detection.meta && detection.meta.epoch) {
    var ms = detection.meta.epoch.seconds * 1000
    var local = formatDate(new Date(ms))
    return { text: "→ " + local + " · " + relative(ms - when), copy: local }
  }

  if (detection.primary === "color") return colorInstant(detection.value)

  var unit = unitInstant(detection.value)
  if (unit) return unit

  var math = evalMath(detection.value)
  if (math !== null) return { text: "= " + math, copy: math }

  return null
}
