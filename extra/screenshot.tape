# options
# Set Shell "bash"
Set FontFamily "Menlo"
Set FontSize 28
Set LetterSpacing 0
Set LineHeight 1.1
 # this is overly tall/wide, we crop later
Set Width 1600
Set Height 1000
Set Padding 20
Set Theme "Catppuccin Frappe"
Set TypingSpeed 0ms

# get ready
Hide
  Type 'PS1="\\[\\e[38;5;120m\\]λ\\[\\e[0m\\] "' Enter
  Type "clear" Enter
  Sleep 0.1s
Show

# run
Type `tennis diamonds.csv -n --title "Diamond Inventory"` Enter Sleep 0.2s
Screenshot vhs0.png Sleep 0.2s
