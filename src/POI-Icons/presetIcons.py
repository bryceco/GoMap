#!/usr/bin/python3

# Look though the preset files and pull out the names of all referenced icons
# Print them to stdout one per line

import sys, glob, json

for file in glob.glob('../presets/*.json'):
#	print(file)
	f = open(file,)
	d=json.load(f)
	if not isinstance(d,dict):
		continue

	# print(json.dumps(d, indent = 4))

	for k,v in d.items():
	#	print(k)
	#	print(v)
		if 'icon' in v:
			print(v['icon'])
	#	print('')
	#	print(v['icon'])
	#	for i2,(k2,v2) in enumerate(v.items()):
	#		print(k2)
