# bail without bash-completion
declare -F _init_completion >/dev/null || return 2>/dev/null

_tennis() {
  local cur prev
  _init_completion || return

  case "${prev}" in
    --color) COMPREPLY=($(compgen -W "on off auto" -- "${cur}")) ; return ;;
    --theme) COMPREPLY=($(compgen -W "auto dark light" -- "${cur}")) ; return ;;
    -d|--delimiter) COMPREPLY=($(compgen -W ", ; | tab" -- "${cur}")) ; return ;;
    --digits) COMPREPLY=($(compgen -W "1 2 3 4 5 6" -- "${cur}")) ; return ;;
    -t|--title|-w|--width) COMPREPLY=() ; return ;;
  esac

  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "-d --delimiter -n --row-numbers -t --title -w --width --color --digits --theme --vanilla --help --version" -- "${cur}"))
  else
    _filedir csv
    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
  fi
}

complete -F _tennis tennis
