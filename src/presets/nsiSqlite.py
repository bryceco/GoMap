#!/usr/bin/python3

# Converts nsi_presets.json to a sqlite db
# Not currently used, but maybe in the future when NSI is unbearably large
#
# Output can be piped to sqlite3 to create the database

import json

file = open("nsi_presets.json")
data = json.load(file)

print("""
create table brands(
	id INTEGER PRIMARY KEY,
	featureID TEXT,
	geometry INTEGER,
	icon TEXT,
	matchScore REAL,
	name TEXT
);
create table fields(
	id INTEGER,
	field TEXT,
	foreign key (id) references brands(id)
);
CREATE INDEX fields_index ON fields (id);

create table locationSet(
	id INTEGER,
	location TEXT,
	include INTEGER,
	foreign key (id) references brands(id)
);
CREATE INDEX locationSetIndex ON locationSet (id);

create table terms(
	id INTEGER,
	term TEXT,
	foreign key (id) references brands(id)
);
CREATE INDEX termsIndex ON terms (id);

create table tags(
	id INTEGER,
	key TEXT,
	value TEXT,
	foreign key (id) references brands(id)
);
CREATE INDEX tagsIndex ON tags (id);

create table addTags(
	id INTEGER,
	key TEXT,
	value TEXT,
	foreign key (id) references brands(id)
);
CREATE INDEX addTagsIndex ON addTags (id);
""")

geom_map={
	"point": 1,
	"line": 2,
	"vertex": 4,
	"area": 8,
	"relation": 16
}
location_map={
	"include": 1,
	"exclude": 0
}

id = -1

presets = data["presets"]
for featureID in presets:
	id += 1
	dict = presets[featureID]
	name = dict["name"].replace('"','""')
	icon = dict.get("icon")
	geom = 0
	for g in dict["geometry"]:
		geom += geom_map[g]
	matchScore = dict["matchScore"]

	print(f'insert into brands(id,featureID,name,icon,geometry,matchScore) values ({id},"{featureID}","{name}","{icon}","{geom}","{matchScore}");')
	tags = dict["tags"]
	for key in tags:
		value = tags[key].replace('"','""')
		print(f'insert into tags(id,key,value) values ("{id}","{key}","{value}");')

	addTags = dict["addTags"]
	for key in addTags:
		value = addTags[key].replace('"','""')
		print(f'insert into addTags(id,key,value) values ("{id}","{key}","{value}");')

	terms = dict["terms"]
	for term in terms:
		term = term.replace('"','""')
		print(f'insert into terms(id,term) values ("{id}","{term}");')

	locationSet = dict["locationSet"]
	for loc in locationSet:
		include = location_map[loc]
		for code in locationSet[loc]:
			print(f'insert into locationSet(id,location,include) values ("{id}","{code}",{include});')
