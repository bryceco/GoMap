#!/usr/bin/python3

# Look though the nsi-presets file and download all referenced brand images

import sys, os, json, requests

file='./nsi_presets.json'
dict=json.load(open(file,))
cnt=0

types = {
"image/jpeg" 	: ".jpg",
"image/png"  	: ".png",
"image/gif"		: ".gif",
"image/webp" 	: ".webp",
"image/bmp"		: ".bmp",
"image/svg+xml" : ".svg"
}

for ident,fields in dict.items():
	if 'imageURL' in fields:
		cnt=cnt+1
		url=fields['imageURL']
		ident=ident.replace("/","_")

		response = requests.get(url, stream=True)
		if response.status_code == 200:
			contentType=response.headers["Content-Type"]
			ext=types.get(contentType,"")
			with open(ident+ext, "wb") as f:
				f.write(response.content)
			print(cnt,url,"-->",ident+ext)
