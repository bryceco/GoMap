#!/usr/bin/env python3
import sys
import xml.etree.ElementTree as ET

ET.register_namespace('', 'urn:oasis:names:tc:xliff:document:1.2')

def process_xliff(path):
    tree = ET.parse(path)
    root = tree.getroot()
    ns = {'x': 'urn:oasis:names:tc:xliff:document:1.2'}

    changed = 0
    for unit in root.findall('.//x:trans-unit', ns):
        note = unit.find('x:note', ns)
        if note is not None and 'Placeholder' in (note.text or ''):
            unit.set('translate', 'no')
            changed += 1

    if changed:
        tree.write(path, encoding='unicode', xml_declaration=True)
        print(f"{path}: marked {changed} unit(s) as translate='no'")

for path in sys.argv[1:]:
    process_xliff(path)
