#!/bin/bash

# KEEP ONLY THE NUMBER OF FILES PER SPECIES DEFINED IN THE OPTIONS

source /etc/birdnet/birdnet.conf
base_dir="$HOME/BirdSongs/Extracted/By_Date"
max_files_species="${MAX_FILES_SPECIES:-0}"
max_files_common="${MAX_FILES_COMMON:-0}"
cd "$base_dir" || true

# If both max_files_species and max_files_common are 0, exit early
if [[ "$max_files_species" -lt 1 ]] && [[ "$max_files_common" -lt 1 ]]; then
    exit 0
fi

# Get unique species
bird_names=$(
    sqlite3 -readonly "$HOME"/BirdNET-Pi/scripts/birds.db <<EOF
.mode column
.headers off
SELECT DISTINCT Com_Name FROM detections;
.quit
EOF
)

# Sanitize the bird names (remove single quotes and replace spaces with underscores)
sanitized_names="$(echo "$bird_names" | tr ' ' '_' | tr -d "'" | grep '[[:alnum:]]')"
# Remove trailing underscores
sanitized_names=$(echo "$sanitized_names" | sed 's/_*$//')
# Define how date works
dateformat=""
if test "$(date -d "-7 days" '+%Y-%m-%d' 2>/dev/null)"; then
    dateformat=" days"
fi

# find detail :
# In the base folders (that corresponds to the BirdSongs/By_date)
# Look for all folders that have the correct species names whatever the date
# Look for files that have the correct format (containing a date), and that have an extension
# For all That are not *.png (as the objective is to limit the number of audio files)
# That were not taken in the past 7 days (= that don't contain the date from that past 7 days). $dateformat is configured as a different variables, as ubuntu accepts "5 days" while alpine accepts only "5"
# That are not included in the file disk_check_exclude.txt that lists files protected from purge
# If the specie name had a "-" in it, it must be converted to "=" to ensure that we have always the same number of "-" separated fields in the filename
# Sort by confidence level (field 4 separated by -)
# Sort by date (1 for year, 2 for month, 3 for days)
# Remove the top x files, corresponding to the files best matching the criteria of confidence + age ; this corresponds to the number of file to keep (in addition to protected files
# Rename species that had a = in their name to - (we don't need anymore - separated fields)
# Duplicate all lines to append .png at the end, to remove the linked png
# This appends a fake "temp" file, so that the sudo rm has at least one file to delete and does not hang
# Delete files, then once all files are deleted echo the number of remaining files

# Load common species names and sanitize them to match folder names (e.g. Blue_Jay)
common_species_file="$HOME/BirdNET-Pi/scripts/common_species_list.txt"
common_species_list=""
if [ -f "$common_species_file" ]; then
    while read -r line; do
        # Extract common name (part after the first underscore)
        com_name=$(echo "$line" | cut -d'_' -f2-)
        if [ -n "$com_name" ]; then
            # Sanitize in the same way as BirdNET-Pi sanitizes folder names
            san_com=$(echo "$com_name" | tr ' ' '_' | tr -d "'" | sed 's/_*$//')
            common_species_list="$common_species_list $san_com"
        fi
    done < "$common_species_file"
fi

# Read each line from the variable and echo the species
while read -r species; do
    # Check if this species is common
    is_common=false
    for common in $common_species_list; do
        if [ "$common" = "$species" ]; then
            is_common=true
            break
        fi
    done

    # Select appropriate threshold
    if [ "$is_common" = true ]; then
        threshold="$max_files_common"
    else
        threshold="$max_files_species"
    fi

    # If threshold is 0 (keep all/unlimited), skip purging for this species
    if [[ "$threshold" -lt 1 ]]; then
        continue
    fi

    echo -n "$species : "
    species_san="${species/-/=}"
    # Dummy file to execute the rm using xargs even if no files are there. Best solution found for code speed
    touch temp
    find */"$species" -type f -name "*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*.*" \
        -not -name "*.png" \
        -not -name "*$(date -d "-7$dateformat" '+%Y-%m-%d')*" \
        -not -name "*$(date -d "-6$dateformat" '+%Y-%m-%d')*" \
        -not -name "*$(date -d "-5$dateformat" '+%Y-%m-%d')*" \
        -not -name "*$(date -d "-4$dateformat" '+%Y-%m-%d')*" \
        -not -name "*$(date -d "-3$dateformat" '+%Y-%m-%d')*" \
        -not -name "*$(date -d "-2$dateformat" '+%Y-%m-%d')*" \
        -not -name "*$(date -d "-1$dateformat" '+%Y-%m-%d')*" \
        -not -name "*$(date '+%Y-%m-%d')*" |
        grep -vFf <(grep -v '^[[:space:]]*$' "$HOME/BirdNET-Pi/scripts/disk_check_exclude.txt") |
        sed "s|$species|$species_san|g" |
        sort -t'-' -k4,4nr -k1,1nr -k2,2nr -k3,3nr |
        tail -n +"$((threshold + 1))" |
        sed "s|$species_san|$species|g" |
        sed 'p; s/\(\.[^.]*\)$/\1.png/' |
        awk 'BEGIN{print "temp"} {print}' |
        xargs sudo rm && echo "success ($(find */"$species" -type f -name "*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*.*" \
        -not -name "*.png" | wc -l)) remaining" || echo "failed ($?)"
# rm to be changed to touch or echo if you want to test without deletion
done <<<"$sanitized_names"
