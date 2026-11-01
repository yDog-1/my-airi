#!/usr/bin/env bash
set -euo pipefail

# Keep logs and credentials outside the Nix store.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/my-airi"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/my-airi"
config_file="${MY_AIRI_PROXY_CONFIG:-$config_dir/cli-proxy-api.yaml}"
proxy_port="${MY_AIRI_PROXY_PORT:-8317}"
tts_port="${MY_AIRI_TTS_PORT:-10101}"
proxy_url="http://127.0.0.1:$proxy_port/v1"
tts_url="http://127.0.0.1:$tts_port"

mkdir -p "$state_dir"
chmod 700 "$state_dir"

if [[ ! -f "$config_file" ]]; then
  echo "CLIProxyAPI config not found: $config_file" >&2
  echo "Create it first (see README.md); then run Codex OAuth login." >&2
  exit 1
fi

proxy_pid=''
tts_pid=''
airi_pid=''

# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  trap - EXIT INT TERM
  for pid in "$airi_pid" "$tts_pid" "$proxy_pid"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for pid in "$airi_pid" "$tts_pid" "$proxy_pid"; do
    if [[ -n "$pid" ]]; then
      wait "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$CODEX_PROXY_BIN" --config "$config_file" >"$state_dir/cli-proxy-api.log" 2>&1 &
proxy_pid=$!
"$AIVIS_BIN" --host 127.0.0.1 --port "$tts_port" --no-use_gpu >"$state_dir/aivisspeech-engine.log" 2>&1 &
tts_pid=$!

wait_ready() {
  local name="$1" url="$2" pid="$3" log="$4"
  local attempt status
  for ((attempt = 0; attempt < 900; attempt++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$name exited unexpectedly. See $log" >&2
      return 1
    fi
    status=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 "$url") || status=000
    # A protected proxy returning 401 is listening; AIRI supplies the API key.
    # This is only a listener check, not a Codex authentication check.
    if [[ "$status" == 200 || ( "$name" == CLIProxyAPI && "$status" == 401 ) ]]; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for $name. See $log" >&2
  return 1
}

wait_ready 'CLIProxyAPI' "$proxy_url/models" "$proxy_pid" "$state_dir/cli-proxy-api.log"
wait_ready 'AivisSpeech Engine' "$tts_url/version" "$tts_pid" "$state_dir/aivisspeech-engine.log"

echo "LLM: $proxy_url  TTS: $tts_url" >&2
echo "Configure these URLs in AIRI; ASR is not configured." >&2
"$AIRI_BIN" "$@" &
airi_pid=$!
finished_pid=''
status=0
wait -n -p finished_pid "$airi_pid" "$proxy_pid" "$tts_pid" || status=$?
if [[ "$finished_pid" != "$airi_pid" ]]; then
  echo "A backend stopped unexpectedly. See $state_dir/*.log" >&2
  exit 1
fi
exit "$status"
