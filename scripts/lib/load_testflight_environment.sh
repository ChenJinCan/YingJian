#!/usr/bin/env bash

load_testflight_environment() {
  local root_dir="$1"
  local env_file="$root_dir/.env.testflight"
  [[ -f "$env_file" ]] || return 0
  local env_line
  while IFS= read -r env_line || [[ -n "$env_line" ]]; do
    [[ -z "${env_line//[[:space:]]/}" || "$env_line" =~ ^[[:space:]]*# ]] && continue
    env_line="${env_line#export }"
    if ! [[ "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      echo "invalid assignment in .env.testflight" >&2
      return 65
    fi
    export "$env_line"
  done < "$env_file"
}
