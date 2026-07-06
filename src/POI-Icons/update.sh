#!/bin/sh

# Download icons from various sources
# Convert them from SVG to PDF
# Build an asset catalog containing the images

GITHUB_RAW="https://raw.githubusercontent.com"
ID_SVG="$GITHUB_RAW/openstreetmap/iD/develop/svg"

# Fetch a URL and save to a file, printing an error (without halting) on failure
fetch() {
	local url="$1"
	local dest="$2"
	curl -fLsS --output "$dest" "$url" 2>/dev/null
}

# Compute the list of icons needed by presets
presetIcons=($(cd ../presets && ./presetIcons.py | sort | uniq | sed 's/$/.svg/'))

# Fetch all required icons
echo "Fetching icons"
for f in "${presetIcons[@]}"; do
	echo $f
	if [[ $f = "iD-"* ]]; then
		f2=${f:3}
		fetch "$ID_SVG/iD-sprite/presets/$f2" ./$f || \
		fetch "$ID_SVG/iD-sprite/fields/crossing_markings/$f2" ./$f || \
		echo "Error: missing iD icon $f2"
	elif [[ $f = "far-"* || $f = "fas-"* ]]; then
		f2=${f:4}
		fetch "$ID_SVG/fontawesome/$f" ./$f || \
		echo "Error: missing fontawesome icon $f"
	elif [[ $f = "pinhead-"* ]]; then
		f2=${f:8}
		fetch "https://pinhead.ink/latest/$f2" ./$f || \
		echo "Error: missing pinhead icon $f2"
	elif [[ $f = "temaki-"* ]]; then
		f2=${f:7}
		fetch "$GITHUB_RAW/ideditor/temaki/main/icons/$f2" ./$f || \
		fetch "$GITHUB_RAW/ideditor/temaki/main/icons/${f2%.svg}-15.svg" ./$f || \
		echo "Error: missing temaki icon $f2"
	elif [[ $f = "maki-"* ]]; then
		f2=${f:5}
		fetch "$GITHUB_RAW/mapbox/maki/main/icons/$f2" ./$f || \
		fetch "$GITHUB_RAW/mapbox/maki/main/icons/${f2%.svg}-15.svg" ./$f || \
		echo "Error: missing maki icon $f2"
	elif [[ $f = "roentgen-"* ]]; then
		f2=${f:9}
		fetch "$GITHUB_RAW/enzet/Roentgen/main/icons/$f2" ./$f || \
		fetch "$GITHUB_RAW/enzet/Roentgen/main/icons/${f2%.svg}-15.svg" ./$f || \
		echo "Error: missing roentgen icon $f2"
	fi
done

for f in "${presetIcons[@]}"; do
	if [ ! -f "$f" ]; then
		echo "Missing preset icon" $f
	fi
done

# build asset catalog
echo "Building asset catalog"
rm -rf ./POI-Icons.xcassets
mkdir POI-Icons.xcassets
for f in *.svg; do
	f2=${f%.*}
	mkdir ./POI-Icons.xcassets/$f2.imageset
	mv $f ./POI-Icons.xcassets/$f2.imageset/$f
	cat > ./POI-Icons.xcassets/$f2.imageset/Contents.json <<EOF
{
  "images" : [
    {
      "filename" : "$f",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "properties" : {
    "preserves-vector-representation" : true
  }
}
EOF
done

git add ./POI-Icons.xcassets

echo "done"
