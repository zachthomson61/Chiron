#!/bin/bash

muscles=("Chest" "Back" "Front Deltoid" "Bicep" "Tricep" "Trapezius" "Forearms" "Quads" "Hamstrings" "Glutes" "Calves" "Abductors" "Adductors" "Abs" "Lower Back")

for muscle in "${muscles[@]}"; do
  clean_name=$(echo "$muscle" | sed 's/ /_/g')
  cat > "Chiron/Assets.xcassets/${clean_name}_Icon.imageset/Contents.json" << JSONEOF
{
  "images" : [
    {
      "filename" : "${muscle} Icon.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSONEOF
done
