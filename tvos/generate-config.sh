#!/bin/bash
# Generate C string literals without executing the configuration as shell code.
set -euo pipefail
CONFIG="${1:?config file path}"
OUTPUT="${2:?output header path}"
VERSION="${3:?legacy version}"
mkdir -p "$(dirname "$OUTPUT")"
emit() {
  local value="$2"
  value="${value%$'\r'}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '#define %s "%s"\n' "$1" "$value"
}
{
  echo '// Generated from config.env. Do not commit.'
  for key in NV_SUPABASE_URL NV_SUPABASE_ANON_KEY NV_TV_LOGIN_BASE NV_TRAKT_CLIENT_ID \
             NV_TRAKT_CLIENT_SECRET NV_SIMKL_CLIENT_ID NV_SIMKL_APP NV_TMDB_API_KEY \
             NV_SEEKR_API_KEY NV_REC_URL NV_DISCORD_CLIENT_ID; do
    value=""
    if [ -f "$CONFIG" ]; then
      value=$(sed -n "s/^$key=//p" "$CONFIG" | head -1)
    fi
    if [ "$key" = NV_SIMKL_APP ] && [ -z "$value" ]; then value="Nuvio"; fi
    emit "$key" "$value"
  done
  emit NV_VERSAO "${VERSION#v}"
} > "$OUTPUT"
