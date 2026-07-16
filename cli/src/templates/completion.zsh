#compdef tennis
compdef _tennis tennis
_tennis() {
  _arguments -s \
{{specs}}
    '*:file:_files -g "*.({{file_extensions}})(-.)" "*(-/)"'
}

if [ "$funcstack[1]" = "_tennis" ]; then
  _tennis
fi
