#!/bin/sh

if [ -z "$GOMAPOSM_USER_PASSWORD" ]; then
	echo "GOMAPOSM_USER_PASSWORD is not set"
	echo "export GOMAPOSM_USER_PASSWORD=user:password"
	exit
fi

# Zip brandIcons2/ from inside the directory so archive entries are relative
# paths (brands/amenity/fast_food/mcdonalds-c9aa1b.png, etc.) rather than
# containing the brandIcons2/ prefix. The server unzipper extracts directly
# into brandIcons2/.
(cd brandIcons2 && zip -rq ../brandIcons2_upload.zip .)

curl --upload-file brandIcons2_upload.zip \
	"ftp://gomaposm.com/public_html/brandIcons2/archive.zip" \
	--user "$GOMAPOSM_USER_PASSWORD"

rm brandIcons2_upload.zip

# Unpack the archive on the server
curl https://gomaposm.com/brandIconsUnzipper2.php

rm -rf brandIcons2/*
