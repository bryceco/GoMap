#!/bin/sh

SC='/tmp/StreetComplete'

(cd /tmp/ && rm -rf StreetComplete && git clone --depth 1 https://github.com/streetcomplete/StreetComplete)

# Get icons

for file in $SC/app/src/main/res/drawable/ic_quest_*.xml; do
	name=$(basename $file)
	name=${name%*.xml}

	mkdir QuestIcons.xcassets/$name.imageset
	python3 VectorDrawable2Svg.py --output-dir "QuestIcons.xcassets/$name.imageset" "$file"

cat > "QuestIcons.xcassets/$name.imageset/Contents.json" <<__EOL__
{
  "images" : [
	{
	"filename" : "$name.svg",
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
__EOL__
done

# git add ./QuestIcons.xcassets/*/*
