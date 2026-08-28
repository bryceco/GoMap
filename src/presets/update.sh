#!/bin/bash

set -e

DIST="https://raw.githubusercontent.com/openstreetmap/id-tagging-schema/main/dist"

# Download presets
presets=(preset_categories
		preset_defaults
		fields
		presets
		deprecated
		discarded)

for preset in "${presets[@]}"; do
	echo $preset
	curl -fLsS --output $preset.json $DIST/$preset.min.json
done

# NSI v8 changed the format of dist/json/nsi.min.json. jsDelivr's @latest tag
# is currently cached at v7; use @8 to explicitly resolve to the latest v8 release.
NSI='https://cdn.jsdelivr.net/npm/name-suggestion-index@8'

# Download NSI geojsons for features
curl -fLsS --output nsi_geojson.json "$NSI/dist/json/featureCollection.min.json"

# Download NSI presets (v8.0+ format: nsi.min.json with "nsi" top-level key)
curl -fLsS --output nsi_presets.json "$NSI/dist/json/nsi.min.json"

# Download address formats
curl -fLsS --output address_formats.json https://raw.githubusercontent.com/openstreetmap/iD/develop/data/address_formats.json

# Download country borders
curl -fLsS --output borders.json https://raw.githubusercontent.com/rapideditor/country-coder/main/src/data/borders.json

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

# remove old translations because sometimes they are stale
(git rm --cached translations/*.json
rm translations/*.json
git clean -fdx translations/.) || true

mkdir translations

for lang in $languages; do
	echo $lang
	curl -fLsS --output translations/$lang.json $DIST/translations/$lang.min.json
done

git add translations/*.json
