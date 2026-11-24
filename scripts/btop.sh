#!/bin/sh
# btop.sh PAPER PAPERDARK INK INKSOFT ACCENT RED GREEN YELLOW BLUE CYAN -- btop in the shell's colours
# (the colours come from Theme.qml via Panes.qml; the theme file is generated here)
paper=$1; pdark=$2; ink=$3; soft=$4; acc=$5; red=$6; green=$7; yellow=$8; blue=$9; cyan=${10}
d="${XDG_RUNTIME_DIR:-/tmp}/projectnier-btop"
mkdir -p "$d/themes"
cat > "$d/themes/nier.theme" <<T
theme[main_bg]="$paper"
theme[main_fg]="$ink"
theme[title]="$ink"
theme[hi_fg]="$acc"
theme[selected_bg]="$ink"
theme[selected_fg]="$paper"
theme[inactive_fg]="$soft"
theme[graph_text]="$soft"
theme[meter_bg]="$pdark"
theme[proc_misc]="$cyan"
theme[cpu_box]="$ink"
theme[mem_box]="$ink"
theme[net_box]="$ink"
theme[proc_box]="$ink"
theme[div_line]="$soft"
theme[temp_start]="$green"
theme[temp_mid]="$yellow"
theme[temp_end]="$acc"
theme[cpu_start]="$green"
theme[cpu_mid]="$yellow"
theme[cpu_end]="$acc"
theme[free_start]="$green"
theme[free_mid]="$green"
theme[free_end]="$green"
theme[cached_start]="$blue"
theme[cached_mid]="$blue"
theme[cached_end]="$blue"
theme[available_start]="$cyan"
theme[available_mid]="$cyan"
theme[available_end]="$cyan"
theme[used_start]="$yellow"
theme[used_mid]="$red"
theme[used_end]="$acc"
theme[download_start]="$blue"
theme[download_mid]="$cyan"
theme[download_end]="$green"
theme[upload_start]="$yellow"
theme[upload_mid]="$red"
theme[upload_end]="$acc"
T
cat > "$d/btop.conf" <<C
color_theme = "nier"
theme_background = True
truecolor = True
C
exec btop --config "$d/btop.conf" --themes-dir "$d/themes"
