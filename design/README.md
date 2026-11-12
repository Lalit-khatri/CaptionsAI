# Design sources

- `AppIcon.svg`: the app icon. Three caption lines with one word lit up, as
  the word-by-word captions do. Render it to the 1024×1024 opaque PNG in
  `CaptionsAI/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`,
  for example with headless Chrome:

  ```sh
  printf '<html><body style="margin:0">%s</body></html>' "$(cat AppIcon.svg)" > /tmp/icon.html
  google-chrome --headless=new --hide-scrollbars --window-size=1024,1024 \
    --screenshot=/tmp/icon.png file:///tmp/icon.html
  magick /tmp/icon.png -alpha off PNG24:AppIcon-1024.png   # App Store rejects alpha
  ```

  iOS applies the rounded mask itself, so the artwork is a full-bleed square.
