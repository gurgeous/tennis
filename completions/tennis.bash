# bail without bash-completion
declare -F _init_completion >/dev/null || return 2>/dev/null

_tennis() {
  local cur prev
  _init_completion || return

  case "$prev" in
    --color|-c) COMPREPLY=( $(compgen -W "auto never always" -- "$cur") ); return ;;
    --theme)    COMPREPLY=( $(compgen -W "auto dark light"   -- "$cur") ); return ;;
    -t|--title) return ;;
  esac

  if [[ $cur == -* ]]; then
    COMPREPLY=( $(compgen -W "--color --theme -n --row-numbers -t --title" -- "$cur") )
  else
    _filedir csv
    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
  fi
}

complete -F _tennis tennis
