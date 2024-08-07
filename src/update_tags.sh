#!/bin/sh

# Tag all commits with version changes in the project

if [ -z "$(git status --porcelain)" ]; then
	echo ""
else
    echo "Commit pending changes and try again"
    exit 1
fi

git log -p -- 'iOS/Go Map!!.xcodeproj/project.pbxproj' |
egrep '(^commit|([+].*MARKETING))' |
sed 's/;//' |
awk '/commit/ { commit = $2 } /MARKETING/ { print "git tag", $4, commit }' |
uniq |
sh
git push --tags
