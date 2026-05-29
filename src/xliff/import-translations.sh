#!/bin/bash

if [ -z "$WEBLATE_TOKEN" ]; then
	echo "WEBLATE_TOKEN is not set"
	exit
fi

WEBLATE_REPO="https://hosted.weblate.org/api/projects/go-map/repository/"
PROJECT="../iOS/Go Map!!.xcodeproj/"
TMP_XLIFF=/tmp/xliff


# Tell weblate to commit changes that translators have made
curl -d operation=commit -H "Authorization: Token $WEBLATE_TOKEN" $WEBLATE_REPO

# Tell weblate to push updated XLIFF files to our repository
curl -d operation=push -H "Authorization: Token $WEBLATE_TOKEN" $WEBLATE_REPO

# Download the updated XLIFFs to the local machine
git pull

# Strip empty translations
sed -i ''  '/<target\/>/d' *.xliff

# Repair broken target language entries
for f in *.xliff; do
	LANG=$(echo $f | sed s/\.xliff//)
	sed -i '' "s/target-language=\"[^\"]*\"/target-language=\"$LANG\"/" $f
done

# Import translators' XLIFFs to update .strings files
for f in *.xliff; do
	xcodebuild -importLocalizations -localizationPath $f -project "$PROJECT"
done
