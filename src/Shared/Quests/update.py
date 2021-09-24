#!/usr/bin/python3

# Dig through StreetComplete to generate a Quests.json file

import os, json, re, xml, xml.dom, xml.dom.minidom

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
titles = []

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
		match = re.search('=\s*R\.string\.(quest_[a-zA-Z_]+_title)',data,re.MULTILINE)
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
			titles.append(title)
# write Quests.json
s = json.dumps(dict, indent=4)
f = open("./Quests.json", "w")
f.write(s)
f.close()

# Get translations
dir=SC+"/app/src/main/res/"
for (dirpath, dirnames, filenames) in os.walk(dir):
	# locate translation file
	match=re.match(".*/values-([a-zA-Z_]+)$",dirpath)
	if match == None:
		continue
	if not ("strings.xml" in filenames):
		continue
	lang = match.groups()[0]

	# parse XML for strings
	text = ""
	tree = xml.dom.minidom.parse(dirpath+"/strings.xml")
	collection = tree.documentElement
	for element in collection.getElementsByTagName("string"):
		name = element.getAttribute('name')
		if name in titles:
			s = element.firstChild.nodeValue
			s = s.strip('"').rstrip('"')
			text = text + '"' + name + '" = "' + s + '";\n'
	# write strings file
	dir = "strings/"+lang+".lproj"
	if not os.path.exists(dir):
		os.mkdir(dir)
	f = open(dir+"/quest.strings", "w")
	f.write(text)
	f.close()
os.mkdir("strings/Base.lproj")
os.touch("strings/Base.lproj/quest.strings")
#os.system("git add ./*.strings")

# Get icons
dir = SC+"/app/src/main/res/drawable/"
for icon in icons:
	base=dir+icon
	# convert from xml to svg
	os.system("./VectorDrawable2Svg.py "+base+".xml")
	# convert from svg to png in 3 sizes
	os.system(INKSCAPE+" --export-type=png --export-width=102 "+base+".xml.svg")
	os.rename(base+".xml.png", base+"@3x.png")
	os.system(INKSCAPE+" --export-type=png --export-width=68 "+base+".xml.svg")
	os.rename(base+".xml.png", base+"@2x.png")
	os.system(INKSCAPE+" --export-type=png --export-width=34 "+base+".xml.svg")
	os.rename(base+".xml.png", base+".png")
# move icons to icons folder
os.system("/bin/mv "+dir+"*.png ./quest_icons/")
os.system("git add ./quest_icons/*.png")

