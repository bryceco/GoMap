#!/bin/bash

if [ -z "$WEBLATE_TOKEN" ]; then
	echo "WEBLATE_TOKEN is not set"
	exit
fi

WEBLATE_REPO="https://hosted.weblate.org/api/projects/go-map/repository/"
PROJECT="../iOS/Go Map!!.xcodeproj/"
TMPDIR=/tmp/xliff

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

# Export localizations back out to XLIFFs
rm -rf $TMPDIR
LIST=""
for f in *.xliff; do
	LANG=$(echo $f | sed s/\.xliff//)
	LIST="$LIST -exportLanguage $LANG"
done
xcodebuild -exportLocalizations -localizationPath $TMPDIR -project "$PROJECT" $LIST

# Copy XLIFF files back here
cp $TMPDIR/*/Localized\ Contents/*.xliff .

# Make sure newly added strings are tracked by git
find .. -name '*.strings' -print0 | xargs -0 git add
git add *.xliff
git add -u

git status

# Commit locally
git commit -m "Update XLIFF files"

# Push to master
git push origin master

# Tell weblate to pull latest XLIFFs
curl -d operation=pull -H "Authorization: Token $WEBLATE_TOKEN" $WEBLATE_REPO
