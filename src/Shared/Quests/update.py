#!/usr/bin/python3

# Dig through StreetComplete to generate a Quests.json file

import os, json, re

SC='/tmp/StreetComplete'
INKSCAPE="/Applications/Inkscape.app/Contents/MacOS/inkscape"

if os.path.exists(SC):
	print("Using existing",SC)
else:
	os.system("(cd /tmp/ && rm -rf StreetComplete && git clone --depth 1 https://github.com/streetcomplete/StreetComplete)")

# get a list of all quest files
files=[]
for (dirpath, dirnames, filenames) in os.walk(SC+"/app/src/main/java/de/westnordost/streetcomplete/quests"):
	for f in filenames:
		if f.endswith(".kt"):
			files.append(dirpath+"/"+f)

dict = {}

icons = []

# locate all quests definitions
for file in files:
	f = open(file, "r")
	data = f.read()
	f.close()

	# get class name
	match = re.search(r"^class\s+(\w+)\s*:\s*(\w+)<(\w+)>",data,re.MULTILINE)
	if match:

		name = match.groups()[0]
		filter = None
		description = None
		wiki = None
		icon = None
		title = None

		# get filter string
		filterCore = '(nodes|ways|relations)(,\s*(nodes|ways|relations))*\s+with\s+'
		filter1 = '"""\s*(' + filterCore + '[^"]+' + ')"""'
		filter2 = '"\s*(' + filterCore + '[^"]+' + ')"'
		match1 = re.search(filter1,data,re.MULTILINE)
		match2 = re.search(filter2,data,re.MULTILINE)
		if match1:
			filter = match1.groups()[0]
		elif match2:
			filter = match2.groups()[0]

		# get description
		match = re.search('\scommitMessage\s+=\s+"([^"]+)"',data,re.MULTILINE)
		if match:
			description = match.groups()[0]

		# get wiki
		match = re.search('\swikiLink\s+=\s+"([^"]+)"',data,re.MULTILINE)
		if match:
			wiki = match.groups()[0]

		# get icon
		match = re.search('\sicon\s+=\s+R.drawable.([a-z_]+)',data,re.MULTILINE)
		if match:
			icon = match.groups()[0]

		# get title
		match = re.search('=\s*R\.string\.(quest_[a-z_]+_title)',data,re.MULTILINE)
		if match:
			title = match.groups()[0]

		if not filter:
			print(name+": missing filter")
			continue
		elif not description:
			print(name+": missing description")
			continue
		elif not wiki:
			print(name+": missing wiki")
			continue
		elif not icon:
			print(name+": missing icon")
			continue
		elif not title:
			print(name+": missing title")
			continue
		else:
			print(name+": Accepted")
			entry = {}
			entry["description"] = description
			entry["wiki"] = wiki
			entry["icon"] = icon
			entry["filter"] = filter
			entry["title"] = title
			dict[name] = entry

			icons.append(icon)

# write Quests.json
s = json.dumps(dict, indent=4)
f = open("./Quests.json", "w")
f.write(s)
f.close()

# Get icons
dir = SC+"/app/src/main/res/drawable/"
for icon in icons:
	# convert from xml to svg
	os.system("./VectorDrawable2Svg.py "+dir+icon+".xml")
	# convert from svg to png in 3 sizes
	os.system(INKSCAPE+" --export-type=png --export-width=102 "+dir+icon+".xml.svg")
	os.rename(dir+icon+".xml.png", dir+icon+"@3x.png")
	os.system(INKSCAPE+" --export-type=png --export-width=68 "+dir+icon+".xml.svg")
	os.rename(dir+icon+".xml.png", dir+icon+"@2x.png")
	os.system(INKSCAPE+" --export-type=png --export-width=34 "+dir+icon+".xml.svg")
	# move to icons folder
	os.rename(dir+icon+".xml.png", dir+icon+".png")

os.system("/bin/mv "+dir+"*.png ./icons/")
os.system("git add ./icons/*.png")
