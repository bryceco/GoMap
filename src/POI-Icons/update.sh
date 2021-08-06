#!/bin/sh

# Download icons from various sources
# Filter those used by the presets
# Convert them from SVG to PDF
# Build an asset catalog containing the images

NAME=(temaki 									maki)
GIT=(https://github.com/ideditor/temaki.git		https://github.com/mapbox/maki.git)
FILES=('icons/*.svg'							'icons/*.svg')

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

# fetch FontAwesome icons (might require website login)
echo "fetching fontawesome icons"
curl -fLsS --output /tmp/fas.zip https://use.fontawesome.com/releases/v5.15.4/fontawesome-free-5.15.4-web.zip

(cd /tmp/ && unzip -q -o ./fas.zip)
for style in "brands" "regular" "solid"; do
	for f in /tmp/fontawesome-*/svgs/$style/*; do
		f2=${f##*/}
		prefix="fa"${style:0:1}
		mv -f $f ./$prefix"-"$f2
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

# Special case fetching icons created in iD
echo "fetching iD icons"
for f in "${presetIcons[@]}"; do
	if [[ $f = "iD-"* ]]; then
		f2=${f:3}
		echo $f2
		curl -fLsS --output ./$f "https://raw.githubusercontent.com/openstreetmap/iD/develop/svg/iD-sprite/presets/$f2"
	fi
done

for f in "${presetIcons[@]}"; do
	if [ ! -f "$f" ]; then
		echo "Missing preset icon" $f
	fi
done

# convert from svg to pdf
rm -f *.pdf
export SOURCE_DATE_EPOCH=1521324801 # set CreationDate within PDF so files don't change unnecessarily
/Applications/Inkscape.app/Contents/MacOS/inkscape --export-type=pdf *.svg
rm *.svg

# build asset catalog
echo "Building asset catalog"
rm -rf ./POI-Icons.xcassets
mkdir POI-Icons.xcassets
for f in *.pdf; do
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
