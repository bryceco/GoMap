#!/usr/bin/python3

# Look though the nsi-presets file and download all referenced brand images

import sys, os, json, requests, cv2, getopt

skip = 0

try:
	opts, _ = getopt.getopt(sys.argv[1:],'',['skip='])
except getopt.GetoptError as e:
	print(e)
	sys.exit(2)
for opt, arg in opts:
	if opt in ("--skip"):
		skip = int(arg)
	else:
		print('getBrandIcons.py [--skip <count>]')
		sys.exit()

FILE='./nsi_presets.json'
SIZE=60

dict=json.load(open(FILE,))
dict=dict["presets"]

types = {
	"image/jpeg" 	: ".jpg",
	"image/png"  	: ".png",
	"image/gif"		: ".gif",
	"image/webp" 	: ".webp",
	"image/bmp"		: ".bmp",
	"image/svg+xml" : ".svg"
}

os.system("rm -rf ./brandIcons")
os.mkdir("./brandIcons")
os.chdir("./brandIcons")

headers = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.102 Safari/537.36'}

cnt=0
for ident,fields in dict.items():
	if 'imageURL' in fields:
		cnt=cnt+1
		if cnt < skip:
			continue
		if cnt > 2000000:
			break
		url=fields['imageURL']
		ident=ident.replace("/","_")

		try:
			response = requests.get(url, headers=headers, stream=True)
		except:
			print(cnt,url,"--> *** Error ***")
			continue

		if response.status_code == 200:
			contentType=response.headers["Content-Type"]
			ext=types.get(contentType,"")
			ident=ident+ext
			print(cnt,url,"-->",ident)
			with open(ident, "wb") as f:
				f.write(response.content)

			if ext == ".svg":
				os.system("/Applications/Inkscape.app/Contents/MacOS/inkscape --export-width="+str(SIZE)+" --export-type=png "+ident)
				os.remove(ident)
			else:
				image = cv2.imread(ident)
				if image is None or image.size == 0:
					continue
				size = max( image.shape[0], image.shape[1] )
				if size > SIZE:
					scale = SIZE/size
					image = cv2.resize(image, (0,0), fx=scale, fy=scale)
					if ext == ".gif" or ext == ".bmp":
						ident = ident[:-3]+"png"
					cv2.imwrite(ident,image)
		else:
			print(cnt,url,"***",response.status_code)
