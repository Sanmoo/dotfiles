# Optional http oc shell-export integration.
# Load explicitly with: source ~/.http-oc.zsh
_http_oc_has_export() {
  [[ "$*" == *--export* ]]
}

_http_oc_export_script() {
  local transfer decoded export_shell export_encoded export_value
  local -A destinations
  transfer="$1"
  decoded="${transfer}.decoded"
  : >| "$decoded"
  while IFS=$'\t' read -r export_shell export_encoded; do
    if [[ ! "$export_shell" =~ ^[A-Za-z_][A-Za-z0-9_]*$ || "$export_encoded" == *$'\t'* || -n "${destinations[$export_shell]}" ]]; then
      print -u2 'error: invalid http oc export transfer'
      rm -f -- "$decoded"
      return 1
    fi
    destinations[$export_shell]=1
    if ! base64 --decode >| "$decoded" 2>/dev/null <<< "$export_encoded"; then
      if ! base64 -D >| "$decoded" 2>/dev/null <<< "$export_encoded"; then
        print -u2 'error: invalid http oc export value'
        rm -f -- "$decoded"
        return 1
      fi
    fi
    IFS= read -r -d '' export_value < "$decoded"
    # Validate in the caller's scope. This helper runs in command substitution,
    # where its locals must not shadow an otherwise valid destination name.
    print -r -- "if [[ -v parameters[${(q)export_shell}] && ( \"\${parameters[${(q)export_shell}]}\" == *readonly* || ( \"\${parameters[${(q)export_shell}]}\" != scalar && \"\${parameters[${(q)export_shell}]}\" != scalar-export ) ) ]]; then print -u2 'error: cannot apply shell export ${(q)export_shell}'; return 1; fi"
    print -r -- "export ${(q)export_shell}=${(q)export_value}"
  done < "$transfer"
  rm -f -- "$decoded"
}

http() {
  [[ "$1" == oc ]] || { command http "$@"; return $?; }
  if ! _http_oc_has_export "$@"; then
    command http "$@"
    return $?
  fi

  # This function deliberately has no named locals: every valid destination
  # must be assigned in the caller scope, even when it matches a helper name.
  set -- "$(mktemp "${TMPDIR:-/tmp}/http-oc-export.XXXXXX")" "$@"
  [[ -n "$1" && -e "$1" ]] || {
    print -u2 'error: cannot create http oc export transfer channel'
    return 1
  }
  set -- "$1" "$1.decoded" "${@:2}"
  : >| "$2"
  HTTP_OC_ZSH_INTEGRATION=1 HTTP_OC_EXPORT_FILE="$1" command http "${@:3}"
  set -- "$1" "$2" "$?" "${@:3}"
  if (( $3 != 0 )); then
    rm -f -- "$1" "$2"
    return $3
  fi
  if [[ ! -s "$1" ]]; then
    print -u2 'error: http oc export integration produced no value'
    rm -f -- "$1" "$2"
    return 1
  fi
  if ! eval "$(_http_oc_export_script "$1")"; then
    rm -f -- "$1" "$2"
    return 1
  fi
  rm -f -- "$1" "$2"
  return 0
}
