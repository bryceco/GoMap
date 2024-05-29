# Tag all commits with version changes in the project

git log -p -- 'iOS/Go Map!!.xcodeproj/project.pbxproj' |
egrep '(^commit|([+].*MARKETING))' |
sed 's/;//' |
awk '/commit/ { commit = $2 } /MARKETING/ { print "git tag", $4, commit }' |
uniq |
sh
