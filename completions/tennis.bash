_tennis() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  case "${prev}" in
    --color) COMPREPLY=( $(compgen -W "auto never always" -- "${cur}") ); return ;;
    --theme) COMPREPLY=( $(compgen -W "auto dark light" -- "${cur}") ); return ;;
    -t|--title) return ;;
  esac

  if [[ ${cur} == -* ]]; then
    COMPREPLY=( $(compgen -W "--color --theme -n --row-numbers -t --title" -- "${cur}") )
  else
    COMPREPLY=( $(compgen -f -X '!*.csv' -- "${cur}") $(compgen -d -- "${cur}") )
    [[ ${#COMPREPLY[@]} -eq 0 ]] && COMPREPLY=( $(compgen -f -- "${cur}") )
  fi
}

complete -o nospace -F _tennis tennis
