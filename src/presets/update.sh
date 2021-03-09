#!/bin/bash

DIST="https://raw.githubusercontent.com/openstreetmap/id-tagging-schema/main/dist"

# Download presets
presets=(preset_categories
		preset_defaults
		fields
		presets)

for preset in ${presets[*]}; do
	echo $preset
	curl -fLsS $DIST/$preset.min.json > $preset.json
done

# Download NSI presets
curl -fLsS --output nsi_presets.json https://raw.githubusercontent.com/osmlab/name-suggestion-index/main/dist/presets/nsi-id-presets.min.json

# Download address formats
curl -fLsS https://raw.githubusercontent.com/openstreetmap/iD/develop/data/address_formats.json > address_formats.json

git add *.json


# Download translation files

# python script to extract languages that are at least 30% translated
GET_LANGS=$(cat <<EOF
import sys, json
dict=json.load(sys.stdin)
for index,(k,v) in enumerate(dict.items()):
	pct=v['pct']
	if pct >= 0.3:
		print(k)
EOF
)

languages=$(curl -fLsS $DIST/translations/index.json |
python3 -c "$GET_LANGS")

for lang in ${languages[*]}; do
	echo $lang
    curl -fLsS $DIST/translations/$lang.min.json > translations/$lang.json
done

git add translations/*.json
