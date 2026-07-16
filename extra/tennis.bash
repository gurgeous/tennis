declare -F _init_completion >/dev/null || return 2>/dev/null

_tennis() {
  local cur prev
  _init_completion || return

  case "${prev}" in
    -t|--title) COMPREPLY=() ; return ;;
    --border) COMPREPLY=() ; return ;;
    --deselect) COMPREPLY=() ; return ;;
    --select) COMPREPLY=() ; return ;;
    --sort) COMPREPLY=() ; return ;;
    --head) COMPREPLY=() ; return ;;
    --tail) COMPREPLY=() ; return ;;
    --filter) COMPREPLY=() ; return ;;
    -b) COMPREPLY=() ; return ;;
    -bb) COMPREPLY=() ; return ;;
    -bbb) COMPREPLY=() ; return ;;
    --width) COMPREPLY=($(compgen -W "auto min max" -- "${cur}")) ; return ;;
    --color) COMPREPLY=() ; return ;;
    -d|--delimiter) COMPREPLY=($(compgen -W ", ; | tab" -- "${cur}")) ; return ;;
    --digits) COMPREPLY=($(compgen -W "1 2 3 4 5 6" -- "${cur}")) ; return ;;
    --scale) COMPREPLY=() ; return ;;
    --rscale) COMPREPLY=() ; return ;;
    --table) COMPREPLY=() ; return ;;
    --theme) COMPREPLY=() ; return ;;
  esac

  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "-n --row-numbers -t --title --border -p --pager --peek -z --zebra --deselect --select --sort -r --reverse --shuffle --shuf --head --tail --filter -b -bb -bbb --width --color -d --delimiter --digits --scale --rscale --table --theme --vanilla -h --help -v --version" -- "${cur}"))
  else
    _filedir '@(csv|tsv|db|json|jsonl|ndjson|sqlite|sqlite3)'
    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
  fi
}

complete -F _tennis tennis
