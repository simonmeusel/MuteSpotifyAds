cd Assets.xcassets/AppIcon.appiconset

convert -background transparent -fill 'hsb(0%,0%,0%)' -font /System/Library/Fonts/Apple\ Symbols.ttf -pointsize 700 -size 512x512 -gravity North label:☂ icon_512.png

for size in 16 32 128 256
do
    echo "$size"
    ratio=$(echo "$size / 512 * 100" | bc -l)%
    echo "$ratio"
    convert icon_512.png -resize "$ratio" "icon_$sizex$size.png"
done
