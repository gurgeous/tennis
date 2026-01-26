# tennis fish shell completion

function __fish_tennis_no_subcommand --description 'Test if there has been any subcommand yet'
    for i in (commandline -opc)
        if contains -- $i completion
            return 1
        end
    end
    return 0
end

complete -c tennis -n '__fish_tennis_no_subcommand' -f -l color -r -d 'Turn color off and on with auto|never|always'
complete -c tennis -n '__fish_tennis_no_subcommand' -f -l theme -r -d 'Select color theme auto|dark|light'
complete -c tennis -n '__fish_tennis_no_subcommand' -f -l row-numbers -s n -d 'Turn on row numbers'
complete -c tennis -n '__fish_tennis_no_subcommand' -f -l title -s t -r -d 'Add a pretty title at the top'
complete -c tennis -n '__fish_tennis_no_subcommand' -f -l help -s h -d 'show help'
complete -c tennis -n '__fish_tennis_no_subcommand' -f -l version -s v -d 'print the version'
complete -c tennis -n '__fish_seen_subcommand_from completion' -f -l help -s h -d 'show help'
complete -x -c tennis -n '__fish_seen_subcommand_from completion; and not __fish_seen_subcommand_from help h' -a 'help' -d 'Shows a list of commands or help for one command'
