# Records docs/demo.gif. Run it with scripts/record-demo.sh, which sets DEMO_DIR.
Output "docs/demo.gif"

Set Shell "bash"
Set FontFamily "DejaVuSansM Nerd Font Mono"
Set FontSize 16
Set Width 1600
Set Height 820
Set Padding 12
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set TypingSpeed 0
Set Framerate 24

Hide
Type `export HOME="$DEMO_DIR/home" YAZI_CONFIG_HOME="$DEMO_DIR/config"; cd "$HOME/data" && clear && yazi`
Enter
Sleep 7s
Show

# customers.csv: summarized view
Sleep 3s
# K at the top switches to standard view
Type "K"
Sleep 2.5s
# scroll rows, then columns
Type "J"
Sleep 1s
Type "J"
Sleep 1.2s
Type "L"
Sleep 0.8s
Type "L"
Sleep 0.8s
Type "L"
Sleep 1.5s
Type "H"
Sleep 0.5s
Type "H"
Sleep 0.5s
Type "H"
Sleep 1s
# events.avro, events.json
Type "j"
Sleep 2.2s
Type "j"
Sleep 2.2s
# shop.duckdb: database view
Type "j"
Sleep 3s
Type "L"
Sleep 0.8s
Type "L"
Sleep 1.5s
# trips.parquet: standard, then summarized
Type "j"
Sleep 2.5s
Type "K"
Sleep 4s
