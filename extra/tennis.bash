declare -F _init_completion >/dev/null || return 2>/dev/null

_tennis() {
  local cur prev
  _init_completion || return

  case "${prev}" in
    -t|--title) COMPREPLY=() ; return ;;
    --border) COMPREPLY=($(compgen -W "ascii_rounded basic basic_compact compact compact_double dots double heavy light markdown none psql reinforced restructured rounded single thin with_love" -- "${cur}")) ; return ;;
    --color) COMPREPLY=($(compgen -W "auto off on" -- "${cur}")) ; return ;;
    --completion) COMPREPLY=($(compgen -W "bash zsh" -- "${cur}")) ; return ;;
    --delimiter) COMPREPLY=($(compgen -W ", ; | tab" -- "${cur}")) ; return ;;
    --digits) COMPREPLY=($(compgen -W "1 2 3 4 5 6" -- "${cur}")) ; return ;;
    --head) COMPREPLY=() ; return ;;
    --tail) COMPREPLY=() ; return ;;
    --theme) COMPREPLY=($(compgen -W "auto dark light" -- "${cur}")) ; return ;;
    --width) COMPREPLY=() ; return ;;
  esac

  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "-n --row-numbers -t --title --border --color --completion --delimiter --digits --head --tail --theme --vanilla --width --help --version " -- "${cur}"))
  else
    _filedir csv
    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
  fi
}

complete -F _tennis tennis
