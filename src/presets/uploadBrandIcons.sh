#!/bin/sh

if [ -z "$GOMAPOSM_USER_PASSWORD" ]; then
        echo "GOMAPOSM_USER_PASSWORD is not set"
        echo "export GOMAPOSM_USER_PASSWORD=user:password"
        exit
fi

cd brandIcons/

# remove file extensions
for f in *.*; do
	mv $f "${f%.*}"
done

# create a zip file
zip archive.zip *

curl --upload-file archive.zip ftp://gomaposm.com/public_html/brandIcons/ --user $GOMAPOSM_USER_PASSWORD

# unzip the archive on the server side
curl https://gomaposm.com/brandIconsUnzipper.php



# old way of uploading:
# ls | xargs -I % curl -T "{%}" ftp://gomaposm.com/public_html/brandIcons/ --user $GOMAPOSM_USER_PASSWORD
