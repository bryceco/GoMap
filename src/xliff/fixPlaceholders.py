#!/usr/bin/env python3
import re
import sys
import xml.etree.ElementTree as ET

ET.register_namespace('', 'urn:oasis:names:tc:xliff:document:1.2')

# Only match Interface Builder's generated trailer, e.g.
#   Class = "UILabel"; ObjectID = "abc-de-fgh"; Note = "Placeholder - do not translate";
IB_PLACEHOLDER_NOTE = re.compile(r'Note\s*=\s*"\s*Placeholder\b', re.IGNORECASE)

def process_xliff(path):
    tree = ET.parse(path)
    root = tree.getroot()
    ns = {'x': 'urn:oasis:names:tc:xliff:document:1.2'}

    changed = 0
    for unit in root.findall('.//x:trans-unit', ns):
        note = unit.find('x:note', ns)
        if note is not None and IB_PLACEHOLDER_NOTE.search(note.text or ''):
            unit.set('translate', 'no')
            changed += 1

    if changed:
        tree.write(path, encoding='UTF-8', xml_declaration=True)
        print(f"{path}: marked {changed} unit(s) as translate='no'")

for path in sys.argv[1:]:
    process_xliff(path)
