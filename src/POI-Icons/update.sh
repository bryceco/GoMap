#!/bin/sh

# Download icons from various sources
# Build an asset catalog containing the images

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# Download all repos as tarballs in parallel
echo "Downloading icon repositories..."
mkdir -p "$TMPDIR_WORK/iD" "$TMPDIR_WORK/maki" "$TMPDIR_WORK/temaki" "$TMPDIR_WORK/roentgen"

curl -fLsS "https://github.com/openstreetmap/iD/archive/develop.tar.gz"    | tar -xz -C "$TMPDIR_WORK/iD"       --strip-components=1 &
curl -fLsS "https://github.com/mapbox/maki/archive/main.tar.gz"            | tar -xz -C "$TMPDIR_WORK/maki"     --strip-components=1 &
curl -fLsS "https://github.com/ideditor/temaki/archive/main.tar.gz"        | tar -xz -C "$TMPDIR_WORK/temaki"   --strip-components=1 &
curl -fLsS "https://github.com/enzet/Roentgen/archive/main.tar.gz"         | tar -xz -C "$TMPDIR_WORK/roentgen" --strip-components=1 &
wait

# Compute the list of icons needed by presets
presetIcons=($(cd ../presets && ./presetIcons.py | sort | uniq | sed 's/$/.svg/'))

# Copy required icons from local repo copies
echo "Fetching icons"
for f in "${presetIcons[@]}"; do
	echo $f
	if [[ $f = "iD-"* ]]; then
		f2=${f:3}
		cp "$TMPDIR_WORK/iD/svg/iD-sprite/presets/$f2" ./$f 2>/dev/null || \
		cp "$TMPDIR_WORK/iD/svg/iD-sprite/fields/crossing_markings/$f2" ./$f 2>/dev/null || \
		echo "Error: missing iD icon $f2"
	elif [[ $f = "far-"* || $f = "fas-"* ]]; then
		cp "$TMPDIR_WORK/iD/svg/fontawesome/$f" ./$f 2>/dev/null || \
		echo "Error: missing fontawesome icon $f"
	elif [[ $f = "pinhead-"* ]]; then
		f2=${f:8}
		curl -fLsS "https://pinhead.ink/latest/$f2" -o ./$f 2>/dev/null || \
		echo "Error: missing pinhead icon $f2"
	elif [[ $f = "temaki-"* ]]; then
		f2=${f:7}
		cp "$TMPDIR_WORK/temaki/icons/$f2" ./$f 2>/dev/null || \
		cp "$TMPDIR_WORK/temaki/icons/${f2%.svg}-15.svg" ./$f 2>/dev/null || \
		echo "Error: missing temaki icon $f2"
	elif [[ $f = "maki-"* ]]; then
		f2=${f:5}
		cp "$TMPDIR_WORK/maki/icons/$f2" ./$f 2>/dev/null || \
		cp "$TMPDIR_WORK/maki/icons/${f2%.svg}-15.svg" ./$f 2>/dev/null || \
		echo "Error: missing maki icon $f2"
	elif [[ $f = "roentgen-"* ]]; then
		f2=${f:9}
		cp "$TMPDIR_WORK/roentgen/icons/$f2" ./$f 2>/dev/null || \
		cp "$TMPDIR_WORK/roentgen/icons/${f2%.svg}-15.svg" ./$f 2>/dev/null || \
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
