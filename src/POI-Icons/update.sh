#!/bin/sh

# Download icons from various sources
# Filter those used by the presets
# Convert them from SVG to PDF
# Build an asset catalog containing the images

NAME=(temaki 									maki								roentgen)
GIT=(https://github.com/ideditor/temaki.git		https://github.com/mapbox/maki.git	https://github.com/enzet/Roentgen.git)
FILES=('icons/*.svg'							'icons/*.svg'						'icons/*.svg')

# fetch icons from repositories
for index in "${!NAME[@]}"; do
	name=${NAME[index]}
	git=${GIT[index]}
	files=${FILES[index]}

	rm -rf /tmp/$name
	(cd /tmp/ && git clone --depth 1 $git)
	for f in /tmp/$name/$files; do
		f2=${f##*/}
		mv -f $f ./$name"-"$(echo $f2 | sed 's/-15//')
	done
done

# filter out any files not required by presets
presetIcons=($(cd ../presets && ./presetIcons.py | sort | uniq | sed 's/$/.svg/'))
presetStrings=" ${presetIcons[@]} "
for f in *.svg; do
	if [[ ! $presetStrings =~ $f ]]; then
		rm $f
	fi
done

# Special case fetching icons stored by iD
echo "fetching iD icons"
for f in "${presetIcons[@]}"; do
	if [[ $f = "iD-"* ]]; then
		f2=${f:3}
		echo $f2
		curl -fLsS --output ./$f "https://raw.githubusercontent.com/openstreetmap/iD/develop/svg/iD-sprite/presets/$f2"
	elif [[ $f = "far-"* || $f = "fas-"* ]]; then
		f2=${f:4}
		echo $f2
		curl -fLsS --output ./$f "https://raw.githubusercontent.com/openstreetmap/iD/develop/svg/fontawesome/$f"
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
