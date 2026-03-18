# options
# Set Shell "bash"
Set FontFamily "Menlo"
Set FontSize 28
Set LetterSpacing 0
Set Width 1600
Set Height 780
Set Padding 20
Set BorderRadius 16
Set Theme "Oceanic-Next"
Set TypingSpeed 0ms


# get ready
Hide
  Type 'PS1="\\[\\e[38;5;120m\\]λ\\[\\e[0m\\] "' Enter
  Type "clear" Enter
  Sleep 0.1s
Show

# run
Type `tennis diamonds.csv -n --title "Diamond Inventory"` Enter Sleep 0.1s

# screenshot
Screenshot screenshot.png
