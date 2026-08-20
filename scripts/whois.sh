#!/bin/bash

# Selected IP on stdin, lookup on stdout. Declared "network": true in core.jsonc.

set -o pipefail

if ! command -v curl >/dev/null; then
  echo "curl is not installed. sudo pacman -S --needed curl" >&2
  exit 1
fi

ip=$(head -c 256 | tr -d '[:space:]')

# Strip a CIDR suffix and an IPv4 :port. IPv6 keeps its colons.
ip=${ip%%/*}
if [[ $ip =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):[0-9]+$ ]]; then
  ip=${BASH_REMATCH[1]}
fi

if [[ -z $ip ]]; then
  echo "Nothing that looks like an address" >&2
  exit 1
fi

json=$(curl -sf -m 6 "https://ipinfo.io/${ip}/json") || {
  echo "ipinfo.io did not answer for ${ip}" >&2
  exit 1
}

if command -v jq >/dev/null && command -v column >/dev/null; then
  jq -r 'del(.readme) | to_entries | map("\(.key)\t\(.value)") | join("\n")' <<<"$json" | column -t -s $'\t'
else
  echo "$json"
fi
