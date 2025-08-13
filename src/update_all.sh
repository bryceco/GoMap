./precheck_git.sh || exit 1
./quitXcode.sh || exit 1
(cd presets && ./update.sh) # fetches latest presets.json, etc. files and NSI
(cd presets && ./getBrandIcons.py) # downloads images from various websites and converts them to png as necessary
(cd presets && ./uploadBrandIcons.sh) # uploads imagery to gomaposm.com where they can be downloaded on demand at runtime (password required)
(cd POI-Icons && ./update.sh) # fetches maki/temaki icons
(cd xliff && ./update.sh) # downloads latest translations from weblate (password required). This step is very noisy and produces many pages of warnings that can be ignored.
