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

blacklist = [
	"AddBollardType",	# unsupported filter
	"AddCrossing"		# too complicated
]
keyList = {
	"AddParkingAccess": "access",
	"AddTrafficSignalsButton": "button_operated",
}

# locate all quests definitions
for file in files:
	f = open(file, "r")
	data = f.read()
	f.close()

	# get class name
	match = re.search(r"^class\s+(\w+)\s*:\s*(\w+)<(\w+)>",data,re.MULTILINE)
	if match:
		name = match.groups()[0]
		if name in blacklist:
			print(name+": Blacklisted")
			continue

		filter = None
		description = None
		wiki = None
		icon = None
		title = None
		key = None

		if name in keyList:
			key = keyList[name]

		# get lists that might be joined together and embedded in filters
		origData = data
		for match in re.finditer('\s([a-zA-Z0-9_]+)\s*=\s*listOf\(\s*("([^"]+)"(,\s*("([^"]+)"))*\s*)',origData,re.MULTILINE):
			ident = match.groups()[0]
			list = match.groups()[1]
			# join the list into "a|b|c" string
			list = re.sub('\s*",\s*"',"|",list)
			list = re.sub('\s*"\s*',"",list)
			# replace joinToString instances
			data = re.sub('\$\{'+ident+'\s*\.\s*joinToString\(\s*"|"\s*\)\}',list,data)

		# get filter string
		filterCore = '(nodes|ways|relations)(,\s*(nodes|ways|relations))*\s+with\s+'
		filter1 = '"""\s*(' + filterCore + '[^"]+' + ')"""'
		filter2 = '"\s*(' + filterCore + '[^"]+' + ')"'
		filter = ""
		filters = []
		for match in re.finditer(filter1,data,re.MULTILINE):
			f = match.groups()[0]
			filters.append(f)
			if len(f) > len(filter):
				filter = f
		for match in re.finditer(filter2,data,re.MULTILINE):
			f = match.groups()[0]
			filters.append(f)
			if len(f) > len(filter):
				filter = f
		#print("Filter =",filter)

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

		if len(filter) == 0:
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
			entry["filters"] = filters
			entry["title"] = title
			if key:
				entry["key"] = key
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
			s = s.strip('"').rstrip('"').rstrip('\\')
			text = text + '"' + name + '" = "' + s + '";\n'
	# write strings file
	if lang == "en":
		lang = "Base"
	dir = "strings/"+lang+".lproj"
	if not os.path.exists(dir):
		os.mkdir(dir)
	f = open(dir+"/quest.strings", "w")
	f.write(text)
	f.close()
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

