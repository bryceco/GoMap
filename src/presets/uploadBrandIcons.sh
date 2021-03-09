#!/bin/sh

if [ -z "$GOMAPOSM_USER_PASSWORD" ]; then
        echo "GOMAPOSM_USER_PASSWORD is not set
        echo "export GOMAPOSM_USER_PASSWORD=user:password"
        exit
fi


cd brandIcons/
for f in *; do
	curl -T $f ftp://gomaposm.com/public_html/brandIcons/ --user $GOMAPOSM_USER_PASSWORD
done
