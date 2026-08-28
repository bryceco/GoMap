#!/usr/bin/python3

# Download brand logos for NSI items and save them as <featureID>.png in
# a hierarchical brandIcons2/ directory, mirroring the NSI path structure.
#
# Logo source: wikidata.min.json maps brand:wikidata / operator:wikidata
# Q-IDs to Facebook Graph API or Wikimedia Commons logo URLs, since NSI v8
# removed imageURL from individual items.

import sys, os, json, requests, cv2, getopt, time, shutil
from datetime import datetime

skip = 0

try:
	opts, _ = getopt.getopt(sys.argv[1:], '', ['skip='])
except getopt.GetoptError as e:
	print(e)
	sys.exit(2)
for opt, arg in opts:
	if opt in ("--skip"):
		skip = int(arg)
	else:
		print('getBrandIcons.py [--skip <count>]')
		sys.exit()

FILE          = './nsi_presets.json'
WIKIDATA_URL  = 'https://cdn.jsdelivr.net/npm/name-suggestion-index@latest/dist/wikidata/wikidata.min.json'
FILE_LIST_URL = 'https://gomaposm.com/brandIconsFileList2.php'
SIZE          = 60  # max image dimension in pixels

headers = {'User-Agent': 'GoMapLogoFetcher/1.0 (https://github.com/bryceco/GoMap; bryceco@yahoo.com) requests/2.32'}

def ts():
	return datetime.now().strftime("%H:%M:%S")

# ── Load NSI v8 presets, flatten to featureID -> item ────────────────────────
print("Loading NSI presets...")
with open(FILE) as f:
	raw = json.load(f)
items = {}
for path, path_data in raw['nsi'].items():
	for item in path_data.get('items', []):
		item_id = item.get('id')
		if item_id:
			items[f"{path}/{item_id}"] = item
print(f"  {len(items):,} NSI items")

# ── Load wikidata logo URLs (Q-ID -> URL) ─────────────────────────────────────
print("Downloading wikidata logo map...")
wd = requests.get(WIKIDATA_URL, headers=headers).json()['wikidata']
logo_urls = {}
for qid, entry in wd.items():
	logos = entry.get('logos', {})
	urls = [u for u in [logos.get('facebook'), logos.get('wikidata')] if u]
	if urls:
		logo_urls[qid] = urls
print(f"  {len(logo_urls):,} logo URLs")

# ── Count eligible items (have a wikidata logo URL) ──────────────────────────
eligible = set()
no_logo = 0
for feature_id, item in items.items():
	tags = item.get('tags', {})
	qid = (tags.get('brand:wikidata') or
	       tags.get('operator:wikidata') or
	       tags.get('network:wikidata'))
	if qid and qid in logo_urls:
		eligible.add(feature_id)
	else:
		no_logo += 1
# ── Fetch the list of logos already on the server ────────────────────────────
print("Fetching server file list...")
existing = set(p.lstrip('/') for p in requests.get(FILE_LIST_URL, headers=headers).content.decode().split())
on_server  = len(eligible & existing)
remaining  = len(eligible - existing)
print(f"  {on_server:,} on server, {remaining:,} to fetch, {no_logo:,} with no logo info")

# ── Prepare local output directory ───────────────────────────────────────────
if os.path.exists('./brandIcons2'):
	shutil.rmtree('./brandIcons2')

image_types = {
	"image/jpeg":    ".jpg",
	"image/png":     ".png",
	"image/gif":     ".gif",
	"image/webp":    ".webp",
	"image/bmp":     ".bmp",
	"image/svg+xml": ".svg",
}

# ── Download missing logos ────────────────────────────────────────────────────
# Process brands first (most useful for POI editing), then operators, then transit.
tree_order = {'brands': 0, 'operators': 1, 'transit': 2}
sorted_items = sorted(items.items(),
                      key=lambda kv: (tree_order.get(kv[0].split('/')[0], 99), kv[0]))

cnt = 0
last_wikimedia_request = 0.0
wikimedia_next_gap = 5.0  # seconds to wait before next wikimedia request; raised to 10 after a rate-limit retry
for feature_id, item in sorted_items:
	tags = item.get('tags', {})
	qid = (tags.get('brand:wikidata') or
	       tags.get('operator:wikidata') or
	       tags.get('network:wikidata'))
	if not qid:
		continue
	logo_url_list = logo_urls.get(qid)
	if not logo_url_list:
		continue

	cnt += 1
	if cnt < skip:
		continue
	if feature_id in existing:
		continue

	out_path = './brandIcons2/' + feature_id + '.png'
	os.makedirs(os.path.dirname(out_path), exist_ok=True)

	response = None
	logo_url = None
	for logo_url in logo_url_list:
		while True:
			if 'wikimedia.org' in logo_url:
				elapsed = time.time() - last_wikimedia_request
				if elapsed < wikimedia_next_gap:
					time.sleep(wikimedia_next_gap - elapsed)
				last_wikimedia_request = time.time()
				wikimedia_next_gap = 5.0  # consumed; reset to normal
			try:
				response = requests.get(logo_url, headers=headers, params={"maxlag": 5}, stream=True)
			except Exception as e:
				print(cnt, ts(), logo_url, "--> *** Error ***", e)
				response = None
				break
			if response.status_code in (429, 503):
				delay = int(response.headers.get("Retry-After", 60))
				print(cnt, ts(), logo_url, "***", response.status_code, "- retrying in", delay, "seconds")
				if 'wikimedia.org' in logo_url:
					wikimedia_next_gap = 10.0
				time.sleep(delay + 1)
				continue
			break
		if response is not None and response.status_code == 200:
			break  # success; no need to try fallback URLs
		print(cnt, ts(), logo_url, "***", getattr(response, 'status_code', 'no response'), "- trying fallback" if logo_url is not logo_url_list[-1] else "")

	if response is None or response.status_code != 200:
		continue

	content_type = response.headers.get("Content-Type", "").split(';')[0].strip()
	ext = image_types.get(content_type, "")
	if not ext:
		print(cnt, ts(), logo_url, "*** Unknown content type:", content_type)
		continue

	print(cnt, ts(), logo_url, "-->", out_path)

	if ext == ".svg":
		# Inkscape converts svg -> png of the same base name
		svg_path = out_path[:-4] + '.svg'
		with open(svg_path, "wb") as f:
			f.write(response.content)
		os.system(f"/Applications/Inkscape.app/Contents/MacOS/inkscape --export-width={SIZE} --export-type=png {svg_path}")
		os.remove(svg_path)
	else:
		# Download, resize if needed, and save as PNG
		temp_path = out_path if ext == ".png" else out_path[:-4] + ext
		with open(temp_path, "wb") as f:
			f.write(response.content)
		image = cv2.imread(temp_path)
		if image is None or image.size == 0:
			os.remove(temp_path)
			continue
		h, w = image.shape[:2]
		if max(h, w) > SIZE:
			scale = SIZE / max(h, w)
			image = cv2.resize(image, (0, 0), fx=scale, fy=scale)
		cv2.imwrite(out_path, image)
		if temp_path != out_path:
			os.remove(temp_path)

print(f"\nDone. {cnt:,} logos processed.")
