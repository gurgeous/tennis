#
# Use VHS to generate a screenshot
#

# vhs settings
Set BorderRadius 12
Set FontFamily "MesloLGSDZ Nerd Font"
Set FontSize 16
Set LetterSpacing 0
Set Margin 0
Set Padding 12
Set WindowBar Colorful
Set WindowBarSize 40
Set Theme "Catppuccin Frappe"
Set TypingSpeed 1ms

# set prompt
Type 'PS1="$ "' Enter Type "clear" Enter Sleep 100 ms
# run
Type@1ms "tennis star_wars.csv --title 'Star Wars People'" Enter
# screenshot
Sleep 0.5 Screenshot "/tmp/demo.png" Sleep 0.1
