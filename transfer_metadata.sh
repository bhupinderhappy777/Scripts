#!/bin/bash

# Phase 1 Tags: Write to reliable XMP:TempDate and other tags
DATE_TAG="-XMP:TempDate<photoTakenTime/timestamp"
DATE_FALLBACK="-XMP:TempDate<creationTime/timestamp" 
DESC_TAG="-Description<description"
LAT_TAG="-GPSLatitude<geoData/latitude"
LON_TAG="-GPSLongitude<geoData/longitude"
ALT_TAG="-GPSAltitude<geoData/altitude"
OVERWRITE_FLAG="-overwrite_original_in_place"

echo "Starting robust metadata transfer (Phase 1/2: Initial Write)..."

# Find all image files, handling spaces/special characters safely with -print0
find . -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.tiff" -o -iname "*.raw" \) -print0 | while IFS= read -r -d $'\0' image_file; do

    # Attempt to find the correct sidecar file
    IMAGE_BASE_NAME="${image_file%.*}"

    JSON_FULL="${image_file}.supplemental-metadata.json"
    JSON_SUPPLEM="${IMAGE_BASE_NAME}.*.json" 

    JSON_TO_USE=""

    if [ -f "$JSON_FULL" ]; then
        JSON_TO_USE="$JSON_FULL"
    elif compgen -G "$JSON_SUPPLEM" > /dev/null; then
         JSON_TO_USE=$(compgen -G "$JSON_SUPPLEM" | head -n 1) 
    fi

    if [ -f "$JSON_TO_USE" ]; then
        echo "Processing $image_file using $JSON_TO_USE"

        # Phase 1: Write date to XMP:TempDate and other tags
        exiftool $OVERWRITE_FLAG \
            $DESC_TAG $LAT_TAG $LON_TAG $ALT_TAG \
            -tagsfromfile "$JSON_TO_USE" \
            $DATE_TAG \
            $DATE_FALLBACK \
            "$image_file"
    fi

done

echo ""
echo "Starting robust metadata transfer (Phase 2/2: Final Date Copy)..."

# Phase 2: Copy the date from the XMP:TempDate field to the final DateTimeOriginal tag
# This single ExifTool command is robust and runs outside the file-by-file loop
exiftool -r $OVERWRITE_FLAG "-DateTimeOriginal<XMP:TempDate" .

echo "Metadata transfer complete."
