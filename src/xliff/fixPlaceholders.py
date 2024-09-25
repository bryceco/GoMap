#!/usr/bin/python3

# Look though an xliff file and delete translation units that contain Note = Placholder

import sys, os
from xml.dom.minidom import parse

filename = sys.argv[1]
document = parse(filename)

tag = "Note = \"Placeholder -".lower()
# print(tag)

notes = document.getElementsByTagName("note")
for note in notes:
	child = note.firstChild
	if child != None:
		value = child.nodeValue
		if tag in value.lower():
			# print(value)
			# Remove the parent
			transUnit = note.parentNode
			body = transUnit.parentNode
			body.removeChild(transUnit)
print(document.toprettyxml(indent=" ",newl=""))

