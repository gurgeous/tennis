declare -F _init_completion >/dev/null || return 2>/dev/null

_tennis() {
  local cur prev
  _init_completion || return

  case "${prev}" in
{{case_arms}}
  esac

  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "{{all_flags}}" -- "${cur}"))
  else
    _filedir '{{file_extensions}}'
    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
  fi
}

complete -F _tennis tennis
