# Writing Blip actions

Every action is a JSONC file. The built-in ones are no different from yours:
same format, same directory layout, and yours can shadow or remove them.

| | |
|---|---|
| `~/.config/omarchy/blip/actions/` | your actions |
| `~/.config/omarchy/blip/scripts/` | scripts they call |
| `~/.config/omarchy/blip/packs/<name>/` | a pack, with the same two directories |

The directory is watched. Saving a file is all it takes; no restart.

## A file

```jsonc
{
  "id": "acme.jira",
  "label": "Ticket",
  "icon": "󰠮",
  "when": { "matches": "^[A-Z]{2,10}-[0-9]+$" },
  "run": { "exec": ["xdg-open", "https://jira.acme.com/browse/${text}"] }
}
```

A file may hold one action or an array of them. A file that fails to parse
names itself in `omarchy-shell blip state` and in the shell log rather than
disappearing quietly.

## A script

The selection arrives on **stdin**, the result comes back on **stdout**. Put
the script in `~/.config/omarchy/blip/scripts/`.

```jsonc
{
  "id": "me.slugify",
  "label": "Slugify",
  "when": { "types": ["text"] },
  "run": { "script": "slugify.sh" },
  "output": "replace"
}
```

```bash
#!/bin/bash
tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'
```

The script also gets `BLIP_TYPE`, `BLIP_TYPES`, `BLIP_APP`, and `BLIP_ACTION`
in its environment.

The shipped QR action is one of these. A few lines of `bash` pipe the selection
through `qrencode`, and `"render": "qr"` draws the result.

![A QR code for the selected link](screenshots/qr.png)

## A network action

An action that sends the selection off this machine declares `network: true`.
The shipped `Whois` action is the worked example:

```jsonc
{
  "id": "blip.ip.whois",
  "label": "Whois",
  "icon": "󰇧",
  "network": true,            // the selection leaves this machine
  "host": "ipinfo.io",        // named in the consent dialog
  "when": { "types": ["ip"] },
  "run": { "script": "whois.sh" },
  "output": "show"
}
```

```bash
#!/bin/bash
ip=$(head -c 256 | tr -d '[:space:]')
curl -sf -m 6 "https://ipinfo.io/${ip}/json" | jq -r \
  'del(.readme) | to_entries | map("\(.key)\t\(.value)") | join("\n")' | column -t -s $'\t'
```

A network action stays hidden until *Allow network actions* is switched on, and
the first run asks before anything is sent, naming the action and the host.
Consent is remembered per action id and revocable from the panel or with
`omarchy-shell blip forget`.

Declare `host` on script actions. `exec` actions have it read out of their
command line automatically.

## Another plugin

A running plugin can register an action over IPC and be called back with the
selection:

```bash
omarchy-shell blip register '{
  "id": "quicktranslate.run",
  "label": "Translate",
  "when": { "types": ["text"] },
  "ipc": { "target": "quicktranslate", "method": "run" },
  "output": "show"
}'
```

Blip calls `omarchy-shell <target> <method> <selection>` and routes whatever
comes back. Registrations live as long as the shell does. Register from your
plugin's `Component.onCompleted` and it is always there.

## Types

A selection carries several of these tags at once, most specific first.

| | |
|---|---|
| `url` | `https://…`, `www.…` |
| `email` `ip` `uuid` | one line, exact match |
| `jwt` | three segments that decode to a header and a payload |
| `json` | starts with `{` or `[` and parses |
| `epoch` | 10 or 13 digits inside a plausible date range |
| `base64` `hex` `urlencoded` | decodes to something printable |
| `hash` | hex of MD5, SHA-1, SHA-256, or SHA-512 length |
| `path` | `/…`, `~/…`, `./…`, `file://…`, `src/main.rs:42` |
| `color` | `#1e88e5`, `rgb(…)`, `hsl(…)` |
| `error` | a traceback, an exception, a "command not found" |
| `code` `number` `word` `multiline` `text` | the rest |

`omarchy-shell blip detect "x"` shows what Blip makes of any selection.

## Matching

Every field in `when` must pass. Omit `when` and the action matches everything.

| | |
|---|---|
| `types` | any of these tags; `["*"]` means any selection |
| `notTypes` | none of these tags |
| `matches` | regular expression over the trimmed selection |
| `notMatches` | the inverse |
| `minLength` `maxLength` | characters |
| `app` `notApp` | substring of the focused window's class or title |

Specificity decides the order and `priority` only breaks ties. An action that
asked for `jwt`, or that pinned a `matches`, sorts above one that took anything
at all. Rarer tags sort above common ones.

## Running

Exactly one of these:

| | |
|---|---|
| `exec` | argv array, no shell, so nothing to escape or inject |
| `script` | a file in the sibling `scripts/` directory, selection on stdin |
| `ipc` | `{ "target": …, "method": … }` on another plugin |
| `builtin` | one of Blip's own transforms, listed by `omarchy-shell blip actions` |

`${text}` `${value}` `${enc}` `${url}` `${path}` `${dir}` `${base}` `${line}`
`${type}` `${search}` expand inside `exec` argv, per argument, never through a
shell. They do land in the process table for as long as the command runs, so
prefer `script` for anything you would rather not have visible there.

`${path}` and `${dir}` come back absolute, with a leading `~` already expanded,
since argv never reaches a shell that would do it.

`${search}` is the search engine chosen in the control panel, with the selection
already in it. It backs `blip.search` only. `blip.search.github` carries its own
url, so override that id if you want repos or issues rather than code. Picking Custom there takes a url of your own, where `%s` marks the
spot the selection goes:

```
https://github.com/search?q=%s&type=code
```

`${enc}` works there in place of `%s`, as do the other variables above, so a
custom search can key off `${type}` or send `${base}` rather than the whole
selection. A url with no placeholder at all is refused and Blip falls back to
DuckDuckGo, rather than searching for nothing.

## Results

| `output` | |
|---|---|
| `none` | fire and forget, the default |
| `copy` | put the result on the clipboard |
| `show` | display it in the popup |
| `replace` | copy it and paste it back over the selection |

Plus `icon`, `description`, `key` to pin an accelerator, `confirm: true` to ask
first, `network: true` to declare that the action sends the selection off this
machine, `host` to name where it goes in the consent dialog, `render: "qr"` to
draw a base64 PNG instead of text, and `keepOpen: true` to leave the bar up
afterwards.

## Overriding what ships

Reuse a built-in's id in your own file and yours wins:

```jsonc
{ "id": "blip.search", "label": "Search", "when": { "types": ["*"] },
  "run": { "exec": ["xdg-open", "https://www.google.com/search?q=${enc}"] } }
```

Remove one outright:

```jsonc
{ "id": "blip.run", "disabled": true }
```

Precedence is built-in, then pack, then user.

## Action packs

A pack is a git repository with the same `actions/` and `scripts/` layout as
`~/.config/omarchy/blip/`. Publishing one is pushing that repo anywhere
public; name it `blip-pack-<something>` and the prefix is stripped on
install.

Installing is one line, or none — the panel's PACKS section takes a pasted
URL, and every installed pack lists there with an update and a remove button:

```bash
omarchy-shell blip packAdd https://github.com/someone/blip-pack-devtools
omarchy-shell blip packs                # what is installed, with action counts
omarchy-shell blip packUpdate devtools  # git pull --ff-only
omarchy-shell blip packRemove devtools
```

`packAdd` also takes an absolute local path, which is how you develop one.
New actions appear the moment the clone lands — no restart.

What a pack can and cannot do: its actions rank below your own files, so
anything you define with the same id wins; a *declared* network action stays
hidden until network actions are allowed, and the first send still asks,
naming the host. But a pack's scripts run as you when you click their action,
and a script that does not declare its traffic is not caught by anything —
so install packs the way you install plugins: from authors you trust.

## Command line

```bash
omarchy-shell blip actions      # every action, with its origin and switch state
omarchy-shell blip state        # armed, catalogue size, and any parse errors
omarchy-shell blip detect "x"   # what Blip makes of a selection, popup-free
omarchy-shell blip disable <id> # the same switch the panel flips
omarchy-shell blip enable <id>
omarchy-shell blip set allowNetwork true   # any setting the manifest declares
omarchy-shell blip packAdd <url>           # and packs, packUpdate, packRemove
```
