// node test/run.js
// Each pure module runs in a fresh VM context, so the shipped .js files
// carry no test scaffolding.

process.env.TZ = "UTC"

const fs = require("fs")
const path = require("path")
const vm = require("vm")

const root = path.join(__dirname, "..")

function load(name) {
  const context = { atob, btoa, Buffer, JSON, Math, Date, RegExp, String, Number, Array, Object, isFinite, decodeURIComponent, encodeURIComponent, parseInt, parseFloat }
  vm.createContext(context)
  vm.runInContext(fs.readFileSync(path.join(root, name), "utf8"), context, { filename: name })
  return context
}

const Detect = load("Detect.js")
const Actions = load("Actions.js")
const Transforms = load("Transforms.js")

let passed = 0
const failures = []

function check(name, condition, detail) {
  if (condition) { passed++; return }
  failures.push(name + (detail ? "\n    " + detail : ""))
}

function equal(name, actual, expected) {
  check(name, Object.is(actual, expected), "expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual))
}

function includes(name, list, value) {
  check(name, list.indexOf(value) !== -1, JSON.stringify(value) + " not in " + JSON.stringify(list))
}

function excludes(name, list, value) {
  check(name, list.indexOf(value) === -1, JSON.stringify(value) + " unexpectedly in " + JSON.stringify(list))
}

// Detect

function types(text) {
  return Detect.detect(text).types
}

includes("url", types("https://omarchy.org/plugins?q=1"), "url")
includes("bare www url", types("www.omarchy.org"), "url")
excludes("prose is not a url", types("visit https://omarchy.org today"), "url")
includes("email", types("dhh@hey.com"), "email")
includes("ipv4", types("192.168.1.24"), "ip")
includes("ipv4 with port", types("10.0.0.1:8080"), "ip")
includes("ipv6", types("fe80::1c2b:aeff:fe80:1"), "ip")
includes("uuid", types("6f1c4a52-9c1d-4f0e-90a1-1f5b8b2a77de"), "uuid")
includes("colour", types("#1e88e5"), "color")
includes("uuid is not a hash", types("6f1c4a52-9c1d-4f0e-90a1-1f5b8b2a77de"), "uuid")

const jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
  + ".eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjE1MTYyNDI2MjJ9"
  + ".SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
includes("jwt", types(jwt), "jwt")
excludes("jwt is not read as base64", types(jwt), "base64")
excludes("three dotted words are not a jwt", types("one.two.three"), "jwt")

includes("json object", types('{"a":1,"b":[2,3]}'), "json")
includes("json array", types("[1,2,3]"), "json")
excludes("broken json is not json", types('{"a":1,'), "json")

includes("epoch seconds", types("1755631200"), "epoch")
includes("epoch millis", types("1755631200000"), "epoch")
excludes("small number is not an epoch", types("42"), "epoch")
includes("small number is a number", types("42"), "number")
excludes("plain digits are not a hex blob", types("12345678"), "hex")
includes("hex blob", types("deadbeefcafe1234"), "hex")
includes("sha256 is a hash", types("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), "hash")

includes("base64", types("SGVsbG8gT21hcmNoeSBmcmllbmRz"), "base64")
includes("percent encoded", types("hello%20omarchy%2Fworld"), "urlencoded")

includes("absolute path", types("/etc/hosts"), "path")
includes("home path", types("~/.config/omarchy/shell.json"), "path")
includes("relative path", types("./scripts/qr.sh"), "path")
equal("path with line ref keeps the file", Detect.detect("src/main.rs:42").meta.path.path, "src/main.rs")
equal("path with line ref keeps the line", Detect.detect("src/main.rs:42").meta.path.line, 42)
equal("path basename", Detect.detect("/etc/hosts").meta.path.base, "hosts")
equal("path dirname", Detect.detect("/etc/hosts").meta.path.dir, "/etc")

includes("error text", types("TypeError: cannot read property 'x' of undefined"), "error")
includes("multiline", types("first line\nsecond line"), "multiline")
includes("single word", types("omarchy"), "word")
includes("everything is text", types("just some prose here"), "text")
equal("empty selection has no types", types("   ").length, 0)

// Prose stays prose

excludes("and/or is not a path", types("and/or"), "path")
excludes("24/7 is not a path", types("24/7"), "path")
excludes("TCP/IP is not a path", types("TCP/IP"), "path")
excludes("a date is not a path", types("19/08/2026"), "path")
excludes("prose around a slash is not a path", types("either/or situation"), "path")
includes("two segments with an extension are a path", types("src/main.rs"), "path")
includes("three segments are a path", types("path/to/thing"), "path")

excludes("a clock is not an ip", types("12:30:45"), "ip")
excludes("a mac address is not an ip", types("aa:bb:cc:dd:ee:ff"), "ip")
includes("compressed ipv6 stays an ip", types("2001:db8::8a2e:370:7334"), "ip")
includes("full ipv6 stays an ip", types("2001:db8:0:1:1:1:1:1"), "ip")

excludes("prose mentioning an error is not an error", types("there was an error in the report"), "error")
excludes("a fatal accident is not an error", types("fatal accident on the highway"), "error")
includes("a panic line is an error", types("panic: runtime error: index out of range"), "error")
includes("command not found is an error", types("bash: foo: command not found"), "error")

excludes("prose starting with if is not code", types("if you want to go"), "code")
excludes("prose starting with for is not code", types("for example, see this"), "code")
includes("a function definition is code", types("function foo() {"), "code")
includes("a statement is code", types("const x = 1;"), "code")

excludes("a lowercase word is not base64", types("testtest"), "base64")
excludes("an uppercase word is not base64", types("AAAABBBB"), "base64")

equal("primary type is the most specific", Detect.detect(jwt).primary, "jwt")
equal("url outranks word", Detect.detect("https://omarchy.org").primary, "url")
equal("label", Detect.label("epoch"), "Timestamp")

// Actions

function scan(origin, source, body) {
  return "===" + origin + "::" + source + "===\n" + body + "\n=== EOF ==="
}

const sample = `[
  // a comment
  {
    "id": "demo.open",       /* and a block one */
    "label": "Open",
    "when": { "types": ["url"] },
    "run": { "exec": ["xdg-open", "\${url}"] },
  }
]`

const loaded = Actions.loadCatalog(scan("builtin", "/plugin/actions/core.jsonc", sample))
equal("jsonc parses through comments and trailing commas", loaded.entries.length, 1)
equal("no load errors", loaded.errors.length, 0)
equal("action id survives", loaded.entries[0].id, "demo.open")
equal("run kind", loaded.entries[0].run.kind, "exec")

const broken = Actions.loadCatalog(scan("user", "/u/actions/bad.jsonc", '[{"label":"No id","run":{"builtin":"copy"}}]'))
equal("missing id is rejected", broken.entries.length, 0)
check("missing id is reported", broken.errors.length === 1 && /missing an id/.test(broken.errors[0]), broken.errors[0])

const noRun = Actions.loadCatalog(scan("user", "/u/actions/bad2.jsonc", '[{"id":"x","label":"X"}]'))
check("missing run is reported", noRun.errors.length === 1 && /no usable run/.test(noRun.errors[0]), noRun.errors[0])

const escaping = Actions.loadCatalog(scan("user", "/u/actions/s.jsonc",
  '[{"id":"s","label":"S","run":{"script":"../../../etc/evil.sh"}}]'))
equal("script paths cannot escape their pack", escaping.entries.length, 0)

const overridden = Actions.mergeCatalog([].concat(
  Actions.loadCatalog(scan("builtin", "/plugin/actions/core.jsonc", '[{"id":"blip.copy","label":"Copy","run":{"builtin":"copy"}}]')).entries,
  Actions.loadCatalog(scan("user", "/u/actions/mine.jsonc", '[{"id":"blip.copy","label":"Yank","run":{"builtin":"copy"}}]')).entries))
equal("a user file shadows a built-in by id", overridden[0].label, "Yank")
equal("shadowing does not duplicate", overridden.length, 1)

const removed = Actions.mergeCatalog([].concat(
  Actions.loadCatalog(scan("builtin", "/plugin/actions/core.jsonc", '[{"id":"blip.run","label":"Run","run":{"builtin":"copy"}}]')).entries,
  Actions.loadCatalog(scan("user", "/u/actions/mine.jsonc", '[{"id":"blip.run","disabled":true}]')).entries))
equal("disabled: true removes a built-in", removed.length, 0)

const catalog = Actions.mergeCatalog(Actions.loadCatalog(scan("builtin", "/plugin/actions/core.jsonc", `[
  { "id": "u.open",   "label": "Open",   "priority": 40, "when": { "types": ["url"] },  "run": { "builtin": "copy" } },
  { "id": "u.copy",   "label": "Copy",   "priority": 20, "when": { "types": ["*"] },    "run": { "builtin": "copy" } },
  { "id": "u.search", "label": "Search", "priority": 10, "when": { "types": ["*"] },    "run": { "builtin": "copy" } },
  { "id": "u.jira",   "label": "Ticket", "when": { "matches": "^[A-Z]{2,10}-\\\\d+$" },  "run": { "builtin": "copy" } },
  { "id": "u.term",   "label": "Term",   "when": { "types": ["*"], "app": ["ghostty"] },"run": { "builtin": "copy" } },
  { "id": "u.small",  "label": "Small",  "when": { "types": ["*"], "maxLength": 5 },    "run": { "builtin": "copy" } },
  { "id": "u.remote", "label": "Remote", "network": true, "when": { "types": ["*"] },   "run": { "exec": ["curl", "https://api.example.com/x"] } }
]`)).entries)

function ids(menu) { return menu.all.map(function(action) { return action.id }) }

const urlMenu = Actions.build(catalog, Detect.detect("https://omarchy.org"), { limit: 6 })
equal("url ranks the type-specific action first", urlMenu.all[0].id, "u.open")
excludes("network actions are hidden by default", ids(urlMenu), "u.remote")
excludes("app-scoped actions stay out of other apps", ids(urlMenu), "u.term")
excludes("maxLength is honoured", ids(urlMenu), "u.small")

const allowed = Actions.build(catalog, Detect.detect("https://omarchy.org"), { limit: 6, allowNetwork: true })
includes("network actions appear once allowed", ids(allowed), "u.remote")

const inApp = Actions.build(catalog, Detect.detect("https://omarchy.org"), { limit: 6, app: "com.mitchellh.ghostty" })
includes("app-scoped action appears in its app", ids(inApp), "u.term")

const jira = Actions.build(catalog, Detect.detect("OMARCHY-1421"), { limit: 6 })
includes("regex matcher fires", ids(jira), "u.jira")
equal("a regex match outranks a high-priority generalist", jira.all[0].id, "u.jira")

const narrow = Actions.mergeCatalog(Actions.loadCatalog(scan("builtin", "/p/actions/a.jsonc", `[
  { "id": "n.word",  "label": "Word",   "priority": 30, "when": { "types": ["word"] },              "run": { "builtin": "copy" } },
  { "id": "n.regex", "label": "Ticket", "when": { "matches": "^[A-Z]{2,10}-\\\\d+$" },              "run": { "builtin": "copy" } }
]`)).entries)
equal("a regex outranks a broad tag match",
  Actions.build(narrow, Detect.detect("OMARCHY-1421"), { limit: 6 }).all[0].id, "n.regex")
const notJira = Actions.build(catalog, Detect.detect("omarchy-1421"), { limit: 6 })
excludes("regex matcher does not overreach", ids(notJira), "u.jira")

const capped = Actions.build(catalog, Detect.detect("hello there"), { limit: 2 })
equal("visible is capped", capped.visible.length, 2)
check("the rest overflow", capped.overflow.length === capped.all.length - 2)

const keys = capped.all.map(function(action) { return action.accelerator })
equal("every action gets an accelerator", keys.filter(function(k) { return k }).length, capped.all.length)
equal("accelerators are unique", new Set(keys).size, keys.length)

const explicit = Actions.build(
  Actions.mergeCatalog(Actions.loadCatalog(scan("builtin", "/p/actions/a.jsonc",
    '[{"id":"a","label":"Alpha","key":"z","run":{"builtin":"copy"},"when":{"types":["*"]}}]')).entries),
  Detect.detect("hello"), { limit: 6 })
equal("a declared key wins", explicit.all[0].accelerator, "z")

const detection = Detect.detect("/etc/nginx/nginx.conf")
equal("template text", Actions.expand("${text}", detection), "/etc/nginx/nginx.conf")
equal("template dir", Actions.expand("${dir}", detection), "/etc/nginx")
equal("template base", Actions.expand("${base}", detection), "nginx.conf")
equal("template percent-encoding", Actions.expand("${enc}", Detect.detect("a b&c")), "a%20b%26c")
equal("unknown placeholders are left alone", Actions.expand("${nope}", detection), "${nope}")

const remote = catalog.filter(function(action) { return action.id === "u.remote" })[0]
equal("host is read out of the command", Actions.hostOf(remote, Detect.detect("x")), "api.example.com")

// Packs

const withPacks = Actions.loadCatalog([
  "===packdir::/u/packs/devtools/===",
  scan("pack", "/u/packs/devtools/actions/x.jsonc", '[{"id":"p.x","label":"X","run":{"builtin":"copy"}}]'),
  "===packdir::/u/packs/empty/===",
  scan("user", "/u/actions/mine.jsonc", '[{"id":"m.y","label":"Y","run":{"builtin":"copy"}}]')
].join("\n"))
equal("pack directories are reported", withPacks.packs.map(function(p) { return p.name }).join(","), "devtools,empty")
equal("an empty pack still shows up", withPacks.packs[1].name, "empty")
equal("packdir markers do not eat actions", withPacks.entries.length, 2)

equal("pack name from a git url", Actions.packNameFromSource("https://github.com/you/blip-pack-devtools.git"), "devtools")
equal("pack name from a plain repo", Actions.packNameFromSource("https://github.com/you/K8s-Tools"), "k8s-tools")
equal("pack name from a local path", Actions.packNameFromSource("/home/me/src/blip-jira/"), "jira")
equal("a cased prefix still strips", Actions.packNameFromSource("https://github.com/you/Blip-Pack-DevTools.git"), "devtools")
equal("garbage yields no pack name", Actions.packNameFromSource("https://github.com/you/..."), "")

// The runtime scan opens with a random boundary token; markers inside file
// bodies must be treated as body text, not honoured.
const bounded = Actions.loadCatalog([
  "===blip-scan::deadbeef01234567===",
  "===deadbeef01234567@builtin::/p/actions/a.jsonc===",
  '[{"id":"b.real","label":"Real","run":{"builtin":"copy"}}]',
  "===deadbeef01234567@EOF===",
  "===deadbeef01234567@pack::/u/packs/evil/actions/x.jsonc===",
  '[{"id":"p.decoy","label":"Decoy","run":{"builtin":"copy"}}]',
  "=== EOF ===",
  "===user::/u/actions/forged.jsonc===",
  '[{"id":"p.forged","label":"Forged","run":{"builtin":"copy"}}]',
  "===deadbeef01234567@EOF===",
  "===deadbeef01234567@packdir::/u/packs/evil/===",
].join("\n"))
equal("boundary markers parse", bounded.entries.filter(function(a) { return a.id === "b.real" }).length, 1)
equal("forged markers register nothing", bounded.entries.filter(function(a) { return a.id === "p.forged" || a.id === "p.decoy" }).length, 0)
check("the poisoned file reports itself instead", bounded.errors.length === 1 && /evil\/actions\/x\.jsonc/.test(bounded.errors[0]), bounded.errors.join(" | "))
equal("packdir markers carry the token too", bounded.packs.map(function(p) { return p.name }).join(","), "evil")

check("https sources are accepted", Actions.isPackSource("https://github.com/you/pack.git"))
check("local paths are accepted", Actions.isPackSource("/home/me/src/pack"))
check("http is refused", !Actions.isPackSource("http://github.com/you/pack.git"))
check("ssh urls are refused", !Actions.isPackSource("git@github.com:you/pack.git"))
check("commands are not sources", !Actions.isPackSource("https://x.com/a; rm -rf ~"))
check("pack names cannot traverse", !Actions.isPackName("../escape"))
check("pack names cannot be nested", !Actions.isPackName("a/b"))

const grouped = Actions.groupCatalog(Actions.mergeCatalog([].concat(
  Actions.loadCatalog(scan("builtin", "/plugin/actions/core.jsonc", '[{"id":"a","label":"A","run":{"builtin":"copy"}}]')).entries,
  Actions.loadCatalog(scan("builtin", "/plugin/actions/text.jsonc", '[{"id":"b","label":"B","run":{"builtin":"copy"}}]')).entries,
  Actions.loadCatalog(scan("pack", "/u/packs/devtools/actions/x.jsonc", '[{"id":"c","label":"C","run":{"builtin":"copy"}}]')).entries,
  Actions.loadCatalog(scan("user", "/u/actions/mine.jsonc", '[{"id":"d","label":"D","run":{"builtin":"copy"}}]')).entries,
  [Actions.normalizeAction({ id: "e", label: "E", run: { builtin: "copy" } }, "pack", "ipc").action])))
equal("modules keep catalogue order",
  grouped.map(function(m) { return m.key }).join(","),
  "builtin:core,builtin:text,pack:devtools,runtime,user")
equal("built-in files get friendly titles", grouped[0].title, "Core")
equal("text module title", grouped[1].title, "Text tools")
equal("packs are titled by directory", grouped[2].title, "Devtools")
equal("ipc registrations group together", grouped[3].title, "From other plugins")
equal("user files group together", grouped[4].title, "Your actions")
equal("every action lands in exactly one module",
  grouped.reduce(function(sum, m) { return sum + m.actions.length }, 0), 5)

// Transforms

const NOW = Date.UTC(2026, 7, 19, 12, 0, 0)

const decoded = Transforms.run("jwt.decode", Detect.detect(jwt), NOW)
check("jwt decodes", decoded.ok)
check("jwt payload is shown", decoded.body.indexOf("John Doe") !== -1, decoded.body)
check("an expired token is flagged", /EXPIRED/.test(decoded.title), decoded.title)
equal("an expired token reads as urgent", decoded.tone, "urgent")
check("jwt copies just the payload", decoded.copy.indexOf("alg") === -1, decoded.copy)

const notJwt = Transforms.run("jwt.decode", Detect.detect("hello"), NOW)
equal("jwt decode refuses non-tokens", notJwt.ok, false)

equal("json formats", Transforms.run("json.format", Detect.detect('{"b":2,"a":1}'), NOW).body, '{\n  "b": 2,\n  "a": 1\n}')
equal("json minifies", Transforms.run("json.minify", Detect.detect('{ "a" : 1 }'), NOW).body, '{"a":1}')

equal("base64 decodes", Transforms.run("base64.decode", Detect.detect("SGVsbG8gT21hcmNoeQ=="), NOW).body, "Hello Omarchy")
equal("base64 encodes", Transforms.run("base64.encode", Detect.detect("Hello Omarchy"), NOW).body, "SGVsbG8gT21hcmNoeQ==")
equal("base64 survives a round trip with accents",
  Transforms.run("base64.decode", Detect.detect(Transforms.run("base64.encode", Detect.detect("café ☕"), NOW).body), NOW).body,
  "café ☕")

equal("hex decodes", Transforms.run("hex.decode", Detect.detect("48656c6c6f"), NOW).body, "Hello")
equal("hex decode refuses odd input", Transforms.run("hex.decode", Detect.detect("48656c6c6"), NOW).ok, false)
equal("percent-encoding decodes", Transforms.run("url.decode", Detect.detect("a%20b%2Fc"), NOW).body, "a b/c")

const stamp = Transforms.run("epoch.local", Detect.detect("1755631200"), NOW)
check("epoch decodes", stamp.ok)
check("epoch shows UTC", stamp.body.indexOf("2025-08-19 19:20:00 UTC") !== -1, stamp.body)
check("epoch says how long ago", /ago|in /.test(stamp.body), stamp.body)

equal("upper", Transforms.run("case.upper", Detect.detect("hello there"), NOW).body, "HELLO THERE")
equal("lower", Transforms.run("case.lower", Detect.detect("HELLO There"), NOW).body, "hello there")
equal("title", Transforms.run("case.title", Detect.detect("hello there"), NOW).body, "Hello There")
equal("snake", Transforms.run("case.snake", Detect.detect("helloThere world"), NOW).body, "hello_there_world")
equal("kebab", Transforms.run("case.kebab", Detect.detect("helloThere world"), NOW).body, "hello-there-world")
equal("camel", Transforms.run("case.camel", Detect.detect("hello there world"), NOW).body, "helloThereWorld")

const counted = Transforms.run("count", Detect.detect("one two\nthree"), NOW)
check("count reports characters", counted.body.indexOf("13 characters") !== -1, counted.body)
check("count reports words", counted.body.indexOf("3 words") !== -1, counted.body)
check("count reports lines", counted.body.indexOf("2 lines") !== -1, counted.body)

equal("unknown built-ins fail loudly", Transforms.run("nope", Detect.detect("x"), NOW).ok, false)

// Instant answers

function inst(text) {
  const answer = Transforms.instant(Detect.detect(text), NOW)
  return answer ? answer.text : null
}

equal("math answers inline", inst("23*4+18"), "= 110")
equal("parens and powers", inst("(2+3)^2"), "= 25")
equal("division keeps decimals", inst("10/4"), "= 2.5")
equal("precedence holds", inst("2+3*4"), "= 14")
equal("unary minus", inst("-(2*3)+10"), "= 4")
equal("the answer is copyable", Transforms.instant(Detect.detect("23*4+18"), NOW).copy, "110")
equal("a bare number is not math", inst("42"), null)
equal("a date is not math", inst("2026-08-20"), null)
equal("a range is not math", inst("5-10"), null)
equal("a version is not math", inst("1.2.3"), null)
equal("a phone number is not math", inst("(555)867-5309"), null)
equal("division by zero has no answer", inst("1/0"), null)

equal("miles convert", inst("100 mi"), "→ 160.93 km")
equal("compact units convert", inst("500m"), "→ 1640.42 ft")
equal("fahrenheit converts", inst("100 f"), "→ 37.78 °C")
equal("celsius converts", inst("37 C"), "→ 98.6 °F")
equal("pounds convert", inst("180 lbs"), "→ 81.65 kg")

equal("hex colour converts", inst("#1e88e5"), "→ rgb(30, 136, 229)")
equal("short hex expands", inst("#fff"), "→ rgb(255, 255, 255)")
equal("rgb converts back", inst("rgb(30, 136, 229)"), "→ #1e88e5")
equal("hsl converts", inst("hsl(0, 100%, 50%)"), "→ #ff0000")

const epochAnswer = Transforms.instant(Detect.detect("1755631200"), NOW)
check("an epoch answers with its local time", epochAnswer && epochAnswer.text.indexOf("→ 2025-08-19 19:20:00") === 0, epochAnswer && epochAnswer.text)
check("the epoch answer says how long ago", epochAnswer && / ago|in /.test(epochAnswer.text), epochAnswer && epochAnswer.text)
equal("the epoch answer copies the local time", epochAnswer.copy, "2025-08-19 19:20:00")

equal("prose has no answer", inst("hello there"), null)
equal("a url has no answer", inst("https://omarchy.org"), null)

// Shipped files

const shipped = ["actions/core.jsonc", "actions/text.jsonc"].map(function(file) {
  return scan("builtin", path.join(root, file), fs.readFileSync(path.join(root, file), "utf8"))
}).join("\n")

const builtins = Actions.loadCatalog(shipped)
equal("the shipped catalogue has no errors", builtins.errors.join(" | "), "")
check("the shipped catalogue is not empty", builtins.entries.length > 10, String(builtins.entries.length))

const shippedCatalog = Actions.mergeCatalog(builtins.entries)
equal("shipped ids are unique", shippedCatalog.length, builtins.entries.length)
equal("merging keeps catalogue order",
  shippedCatalog.map(function(a) { return a.id }).join(","),
  builtins.entries.map(function(a) { return a.id }).join(","))

const jwtMenu = Actions.build(shippedCatalog, Detect.detect(jwt), { limit: 6 })
equal("a JWT offers Decode first", jwtMenu.all[0].id, "blip.jwt.decode")
const jsonMenu = Actions.build(shippedCatalog, Detect.detect('{"a":1}'), { limit: 6 })
equal("JSON offers Format first", jsonMenu.all[0].id, "blip.json.format")
const pathMenu = Actions.build(shippedCatalog, Detect.detect("/etc/hosts"), { limit: 6 })
equal("a path offers Open first", pathMenu.all[0].id, "blip.path.open")
const proseMenu = Actions.build(shippedCatalog, Detect.detect("some ordinary prose"), { limit: 6 })
equal("prose starts with Copy", proseMenu.all[0].id, "blip.copy")

const declaredNetwork = ["blip.ip.whois"]

for (const action of shippedCatalog) {
  check("every shipped action has an icon: " + action.id, action.icon.length > 0)
  check("no shipped action is silently networked: " + action.id,
    action.network === declaredNetwork.includes(action.id))
  if (action.network) {
    check("networked shipped actions name their host: " + action.id, action.host.length > 0)
  }
}

const hosted = Actions.loadCatalog(scan("user", "/u/actions/net.jsonc",
  '[{"id":"n.api","label":"Lookup","network":true,"host":"api.example.org","when":{"types":["*"]},"run":{"script":"x.sh"}}]')).entries[0]
equal("a declared host survives normalization", hosted.host, "api.example.org")
equal("a declared host feeds the consent dialog", Actions.hostOf(hosted, Detect.detect("x")), "api.example.org")

const ipMenu = Actions.build(shippedCatalog, Detect.detect("8.8.8.8"), { limit: 6 })
excludes("whois hides until network actions are allowed", ids(ipMenu), "blip.ip.whois")
const ipAllowed = Actions.build(shippedCatalog, Detect.detect("8.8.8.8"), { limit: 6, allowNetwork: true })
includes("whois appears once they are", ids(ipAllowed), "blip.ip.whois")

if (failures.length) {
  console.error("\n" + failures.length + " failed:\n")
  for (const failure of failures) console.error("  ✗ " + failure)
  console.error("\n" + passed + " passed, " + failures.length + " failed")
  process.exit(1)
}

console.log(passed + " passed")
