#!/usr/bin/env bash
# vim:fileencoding=utf-8:foldmethod=marker


# Flags declaration
declare -A flags    # Associative array, requires Bash 4+
flags[debug]=0


# Argument processing {{{

# Receive "1" (and ONLY 1) file with the cursors: either tar.gz or .zip

# Check if required arguments are present
if [ $# -lt 1 ] || [ $# -gt 2 ]
then
    echo "Error: expected 1 argument."
    echo "Usage: $(basename $0) {-d --debug} cursor_file"
    exit 1
fi

# Parse arguments
if [[ "$*" =~ (^|[[:space:]])-d|--debug($|[[:space:]]) ]]
then
    flags[debug]=1
fi


cursor_src="$1"
test -e "$cursor_src" || cursor_src="$2"
test -e "$cursor_src" || {
    echo "Error: No valid cursor file was provided";
    exit 1
}
cursor_src="$(realpath $cursor_src)"

# }}}


# Main program logic {{{

# There are three things that this program has to do:
#   - Extract the colours of the cursor passed:
#     For every cursor image, extract all the different colours that appear in it
#   - Calculate the "equivalent" colours and repaint a copy of the original images:
#     For every cursor file, create a copy as to not modify the original, calculate the colors that it should have
#     and apply it to them
#   - Generate the xcursor from the png files and conf files:
#     For obtaining the conf files there are two approaches, modifying the ones that xcur2png generate when extracting 
#     the pngs, from the original xcursor file (the only thing to modify is the path), or create them from scratch
#
# Caveats:
#   - Define how "fuzzy" color replacing should be (as to not replace everything except but one color, and keep hues of
#     the color to change)
#   - Have to create the symlinks after modifying the new pngs

# Declarations {{{

color_old="(77, 77, 77, 255)"
color_new="(249, 173, 242, 255)"
color_threshold="30"

declare -A paths    # Associative array for storing all the paths

# Paths are relative to the script execution location
paths[working_dir]="/tmp/$(basename $0 | cut -d. -f1)"
paths[cursor_file]="$cursor_src"
paths[venv]="python-env"
paths[venv_activate]="${paths[venv]}/bin/activate"
paths[gen_folder]="cursor-gen"
paths[pngs_folder]="png-cursors"
paths[decompress_folder]="decompress-folder"
paths[python_script]="pixels.py"
paths[new_cursor_theme]="new-cursor-theme"
paths[called_directory]="$(pwd)"


# Paths that are "convention", so they should not be changed
declare -A CONSTANT_PATHS

CONSTANT_PATHS[cursor_folder]="cursors"
CONSTANT_PATHS[index_theme]="index.theme"


color_to_change=""

# }}}


# Pre-requisites {{{

test -d "${paths[working_dir]}" && rm -fr "${paths[working_dir]}"
mkdir "${paths[working_dir]}" && cd "${paths[working_dir]}"

mkdir -p "${paths[pngs_folder]}" "${paths[gen_folder]}" "${paths[new_cursor_theme]}"

# Decompress the file with the cursor

rm -fr "${paths[decompress_folder]}" \
    && mkdir -p "${paths[decompress_folder]}" \
    && tar xf "${paths[cursor_file]}" -C "${paths[decompress_folder]}" \
    && mv ${paths[decompress_folder]}/*/* . \
    && rm -fr "${paths[decompress_folder]}"

if ! [ -d "${CONSTANT_PATHS[cursor_folder]}" ] || ! [ -e "${CONSTANT_PATHS[index_theme]}" ]
then
    echo "Error: The cursor does not have the expected contents: '${CONSTANT_PATHS[@]}'"
    exit 1
fi

# }}}


# Xcursor to PNG conversion {{{

for xcursor_file in ${CONSTANT_PATHS[cursor_folder]}/*
do
    # Skip symlinks
    test -h "$xcursor_file" && continue

    xcur2png -q -d "${paths[pngs_folder]}" -c "${paths[pngs_folder]}" "$xcursor_file" 2> /dev/null
done

# }}}


# PNG color extraction, conversion and repaint (python script) {{{

if ! test -e "${paths[venv_activate]}"
then
    python -m venv ${paths[venv]}

    source "${paths[venv_activate]}" \
        && pip install -qqq --no-input pillow \
        && deactivate
fi


# Write the python program to a file
cat > "${paths[python_script]}" << END
from PIL import Image
import colorsys
from math import sqrt
from ast import literal_eval
from os import listdir, path, getenv

# Function to calculate Euclidean distance between two colors
def color_distance(color1, color2):
    r1, g1, b1 = color1
    r2, g2, b2 = color2
    return sqrt((r1 - r2) ** 2 + (g1 - g2) ** 2 + (b1 - b2) ** 2)

# Function to check if two colors are within a closeness threshold
def is_color_close(color1, color2, threshold_percent):
    max_distance = sqrt(255**2 + 255**2 + 255**2)  # Max distance in RGB space (≈441.67)
    distance = color_distance(color1, color2)
    return (distance / max_distance) * 100 <= threshold_percent

# Function to calculate the luminance (brightness) of a color
def get_luminance(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

# Function to map a color to the new hue, preserving its luminance and alpha
def map_color_to_new_hue(r, g, b, alpha, new_color_rgb):
    luminance = get_luminance(r, g, b)
    
    # Convert the new color to HSV
    new_color_hsv = colorsys.rgb_to_hsv(new_color_rgb[0] / 255, new_color_rgb[1] / 255, new_color_rgb[2] / 255)
    
    # Map luminance (brightness) to the new color
    new_r, new_g, new_b = colorsys.hsv_to_rgb(new_color_hsv[0], luminance / 255, new_color_hsv[2])
    
    # Convert back to the 0-255 range
    new_r, new_g, new_b = int(new_r * 255), int(new_g * 255), int(new_b * 255)

    return new_r, new_g, new_b, alpha  # Preserve original alpha

# Function to process the image and replace colors within a closeness threshold
def replace_colors_in_image(input_image_path, output_image_path, original_color, new_base_color, threshold_percent):
    img = Image.open(input_image_path).convert("RGBA")
    pixels = img.load()

    width, height = img.size
    for y in range(height):
        for x in range(width):
            r, g, b, alpha = pixels[x, y]

            # Check if the current pixel color is close to the target color
            if is_color_close((r, g, b), original_color[:3], threshold_percent):
                new_r, new_g, new_b, new_alpha = map_color_to_new_hue(r, g, b, alpha, new_base_color)
                pixels[x, y] = (new_r, new_g, new_b, new_alpha)

    img.save(output_image_path)

# Environment variables
src_png_folder = getenv("SRC_PNG", "")
dst_png_folder = getenv("DST_PNG", "")
color_to_change = getenv("COLOR_OLD", "")
new_base_color = getenv("COLOR_NEW", "")
threshold_percent = float(getenv("COLOR_THRESHOLD", "10"))  # Default 10% similarity threshold

if not path.exists(src_png_folder) or not path.exists(dst_png_folder):
    raise RuntimeError("Source or destination folder does not exist.")

original_color = tuple(literal_eval(color_to_change))
new_color = tuple(literal_eval(new_base_color))

for file in listdir(src_png_folder):
    if not file.endswith(".png"):
        continue
    
    input_image_path = path.join(src_png_folder, file)
    output_image_path = path.join(dst_png_folder, file)

    replace_colors_in_image(input_image_path, output_image_path, original_color, new_color, threshold_percent)
END


# Run the python program to extract the current colors and obtain the new ones
source "${paths[venv_activate]}" \
    && SRC_PNG="${paths[pngs_folder]}" DST_PNG="${paths[gen_folder]}" COLOR_OLD="$color_old" COLOR_NEW="$color_new" COLOR_THRESHOLD="$color_threshold" python "${paths[python_script]}" \
    && deactivate \
    || exit 1

# }}}


# Modified PNGs to Xcursor {{{

# Create the index.theme file
cat > "${paths[new_cursor_theme]}/${CONSTANT_PATHS[index_theme]}" <<EOF
[Icon Theme]
Name=Breeze (Plasma 5) custom
EOF

mkdir -p "${paths[new_cursor_theme]}/${CONSTANT_PATHS[cursor_folder]}"

# Copy the original conf files, they are still valid
cp ${paths[pngs_folder]}/*.conf ${paths[gen_folder]}

for conf_file in ${paths[gen_folder]}/*.conf
do
    dst_file="$(basename $conf_file | cut -d. -f1)"
    xcursorgen --prefix "${paths[gen_folder]}" "${conf_file}" "${paths[new_cursor_theme]}/${CONSTANT_PATHS[cursor_folder]}/${dst_file}"
done


# Copy all symlinks from FOLDER 1 to FOLDER 2
find "${CONSTANT_PATHS[cursor_folder]}" -type l | while read -r symlink; do
    # Get the target of the symlink
    target=$(readlink "$symlink")
    
    # Get the filename part of the target (basename)
    target_basename=$(basename "$target")
    
    # Create the symlink in FOLDER 2, pointing to the same file by name (./)
    ln -s "$target_basename" "${paths[new_cursor_theme]}/${CONSTANT_PATHS[cursor_folder]}/$(basename "$symlink")"
done


# Move to the folder with `cursor` folder and `index.theme` file to pack it as a cursor file
cd ${paths[new_cursor_theme]}

# Set permissions to 644 (rw, r, r) for the pertinent files (not dirs)
chmod -R 644 ${CONSTANT_PATHS[cursor_folder]}/* ${CONSTANT_PATHS[index_theme]}

# Pack the folders into a Xcursor file (tar.gz)
xcursor_name="breeze-cursors-custom-color-plasma5.tar.gz"
tar czf "${xcursor_name}" ${CONSTANT_PATHS[cursor_folder]} ${CONSTANT_PATHS[index_theme]}

# Move the Xcursor file to the directory where the script was called
mv "${xcursor_name}" "${paths[called_directory]}"

# }}}

# }}}
