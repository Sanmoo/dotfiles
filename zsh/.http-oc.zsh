# Optional http oc shell-export integration.
# Load explicitly with: source ~/.http-oc.zsh
http() {
  local arg has_export=false transfer decoded shell_name encoded value result_status
  [[ "$1" == oc ]] || { command http "$@"; return $?; }
  for arg in "$@"; do
    case "$arg" in
      --export|--export=*) has_export=true; break ;;
    esac
  done
  if ! $has_export; then
    command http "$@"
    return $?
  fi

  transfer=$(mktemp "${TMPDIR:-/tmp}/http-oc-export.XXXXXX") || {
    print -u2 'error: cannot create http oc export transfer channel'
    return 1
  }
  decoded="${transfer}.decoded"
  : >| "$decoded"
  HTTP_OC_ZSH_INTEGRATION=1 HTTP_OC_EXPORT_FILE="$transfer" command http "$@"
  result_status=$?
  if (( result_status != 0 )); then
    rm -f -- "$transfer" "$decoded"
    return $result_status
  fi
  if [[ ! -s "$transfer" ]]; then
    print -u2 'error: http oc export integration produced no value'
    rm -f -- "$transfer" "$decoded"
    return 1
  fi
  IFS=$'\t' read -r shell_name encoded < "$transfer" || {
    print -u2 'error: invalid http oc export transfer'
    rm -f -- "$transfer" "$decoded"
    return 1
  }
  if [[ ! "$shell_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ || "$encoded" == *$'\t'* ]]; then
    print -u2 'error: invalid http oc export transfer'
    rm -f -- "$transfer" "$decoded"
    return 1
  fi
  if ! base64 --decode >| "$decoded" 2>/dev/null <<< "$encoded"; then
    if ! base64 -D >| "$decoded" 2>/dev/null <<< "$encoded"; then
      print -u2 'error: invalid http oc export value'
      rm -f -- "$transfer" "$decoded"
      return 1
    fi
  fi
  IFS= read -r -d '' value < "$decoded"
  export "$shell_name=$value"
  result_status=$?
  rm -f -- "$transfer" "$decoded"
  return $result_status
}
