#!/bin/bash

set -e

if [ -z "$WEBLATE_TOKEN" ]; then
	echo "WEBLATE_TOKEN is not set"
	exit 1
fi

WEBLATE_REPO="https://hosted.weblate.org/api/projects/go-map/repository/"
PROJECT="../iOS/Go Map!!.xcodeproj/"
TMP_XLIFF=/tmp/xliff


# Export localizations back out to XLIFFs
rm -rf "$TMP_XLIFF"
LANGS=()
for f in *.xliff; do
	lang="${f%.xliff}"
	[ "$lang" = "en" ] && continue  # English is the source language, not a translation target
	LANGS+=(-exportLanguage "$lang")
done
xcodebuild -exportLocalizations -localizationPath "$TMP_XLIFF" -project "$PROJECT" "${LANGS[@]}"

# Copy XLIFF files back here
cp "$TMP_XLIFF"/*/Localized\ Contents/*.xliff .

# Look for notes containing "Placeholder - do not translate" and mark them with translate="no"
./fixPlaceholders.py *.xliff

# Make sure newly added strings are tracked by git
find .. -name '*.strings' -not -path '*/vendor/*' -print0 | xargs -0 git add
git add *.xliff
git add -u

git status

# Commit locally
git commit -m "Update XLIFF files"

# Push our changes so weblate can pull them from our repository
git push

# Tell weblate to pull latest XLIFFs
curl -fLsS -d operation=pull -H "Authorization: Token $WEBLATE_TOKEN" "$WEBLATE_REPO"
