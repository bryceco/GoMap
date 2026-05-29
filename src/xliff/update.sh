#!/bin/bash

# Download XLIFF files from weblate, and convert them to .xcstrings files
./import-translations.sh

# Export strings from our project as XLIFF files, and upload them to weblate
./export-translations.sh
