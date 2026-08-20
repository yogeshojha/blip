#!/bin/bash

# Selection on stdin, base64 PNG on stdout. Rendered by "render": "qr".

set -o pipefail

if ! command -v qrencode >/dev/null; then
  echo "qrencode is not installed. sudo pacman -S --needed qrencode" >&2
  exit 1
fi

qrencode -t PNG -s 6 -m 3 -o - | base64 -w0
