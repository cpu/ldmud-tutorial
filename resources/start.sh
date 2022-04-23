#!/usr/bin/env bash

set -eo pipefail

DOMAIN=lpc.zone
MUD_ROOT=/home/mud/game
TELNET_PORT=4141

TLS_PORT=4242
TLS_KEY="$MUD_ROOT/tls/$DOMAIN.key"
TLS_CERT="$MUD_ROOT/tls/$DOMAIN.crt"
TLS_ISSUER="$MUD_ROOT/tls/$DOMAIN.issuer.crt"

PYTHON_VENV="$MUD_ROOT/python/.venv"
PYTHON_STARTUP="$MUD_ROOT/python/startup.py"

source "$PYTHON_VENV/bin/activate"
$MUD_ROOT/bin/ldmud \
  -D"TLS_PORT=$TLS_PORT" \
  --tls-key="${TLS_KEY}" \
  --tls-cert="${TLS_CERT}" \
  --tls-trustfile="${TLS_ISSUER}" \
  --python-script="$PYTHON_STARTUP" \
  --hard-malloc-limit 0 \
  $TELNET_PORT \
  $TLS_PORT
