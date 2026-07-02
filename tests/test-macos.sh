#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

MOCK_BIN="$TMP_ROOT/bin"
MOCK_STATE="$TMP_ROOT/network-state"
mkdir -p "$MOCK_BIN" "$TMP_ROOT/home"

cat > "$MOCK_STATE" <<'EOF'
WEB_ENABLED=No
WEB_SERVER=old-http.local
WEB_PORT=8080
SECURE_ENABLED=Yes
SECURE_SERVER=old-https.local
SECURE_PORT=8443
EOF

cat > "$MOCK_BIN/route" <<'EOF'
#!/bin/bash
printf '   interface: en0\n'
EOF

cat > "$MOCK_BIN/nc" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$MOCK_BIN/curl" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$MOCK_BIN/open" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$MOCK_BIN/networksetup" <<'EOF'
#!/bin/bash
set -euo pipefail
source "$MOCK_STATE"

write_state() {
  cat > "$MOCK_STATE" <<STATE
WEB_ENABLED=$WEB_ENABLED
WEB_SERVER=$WEB_SERVER
WEB_PORT=$WEB_PORT
SECURE_ENABLED=$SECURE_ENABLED
SECURE_SERVER=$SECURE_SERVER
SECURE_PORT=$SECURE_PORT
STATE
}

case "$1" in
  -listnetworkserviceorder)
    printf '(1) Wi-Fi\n(Hardware Port: Wi-Fi, Device: en0)\n'
    ;;
  -getwebproxy)
    printf 'Enabled: %s\nServer: %s\nPort: %s\nAuthenticated Proxy Enabled: 0\n' "$WEB_ENABLED" "$WEB_SERVER" "$WEB_PORT"
    ;;
  -getsecurewebproxy)
    printf 'Enabled: %s\nServer: %s\nPort: %s\nAuthenticated Proxy Enabled: 0\n' "$SECURE_ENABLED" "$SECURE_SERVER" "$SECURE_PORT"
    ;;
  -setwebproxy)
    WEB_SERVER="$3"; WEB_PORT="$4"; write_state
    ;;
  -setsecurewebproxy)
    SECURE_SERVER="$3"; SECURE_PORT="$4"; write_state
    ;;
  -setwebproxystate)
    [[ "$3" == on ]] && WEB_ENABLED=Yes || WEB_ENABLED=No; write_state
    ;;
  -setsecurewebproxystate)
    [[ "$3" == on ]] && SECURE_ENABLED=Yes || SECURE_ENABLED=No; write_state
    ;;
  *)
    printf 'Unexpected networksetup call: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$MOCK_BIN"/*

export HOME="$TMP_ROOT/home"
export XDG_STATE_HOME="$TMP_ROOT/state"
export MOCK_STATE
export ALLOW_NON_MACOS_TESTS=1
export NETWORKSETUP_BIN="$MOCK_BIN/networksetup"
export ROUTE_BIN="$MOCK_BIN/route"
export NC_BIN="$MOCK_BIN/nc"
export CURL_BIN="$MOCK_BIN/curl"
export OPEN_BIN="$MOCK_BIN/open"

"$ROOT_DIR/macos/codex-proxy" doctor >/dev/null
"$ROOT_DIR/macos/codex-proxy" enable >/dev/null

source "$MOCK_STATE"
[[ "$WEB_ENABLED" == Yes && "$WEB_SERVER" == 127.0.0.1 && "$WEB_PORT" == 10808 ]]
[[ "$SECURE_ENABLED" == Yes && "$SECURE_SERVER" == 127.0.0.1 && "$SECURE_PORT" == 10808 ]]

"$ROOT_DIR/macos/codex-proxy" restore >/dev/null

source "$MOCK_STATE"
[[ "$WEB_ENABLED" == No && "$WEB_SERVER" == old-http.local && "$WEB_PORT" == 8080 ]]
[[ "$SECURE_ENABLED" == Yes && "$SECURE_SERVER" == old-https.local && "$SECURE_PORT" == 8443 ]]

if PROXY_HOST=192.168.1.10 "$ROOT_DIR/macos/codex-proxy" status >/dev/null 2>&1; then
  printf 'Expected non-loopback proxy validation to fail\n' >&2
  exit 1
fi

printf 'All tests passed.\n'
