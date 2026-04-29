#!/bin/sh

set -eu

checkout_dir="${1:?missing Alderis checkout path}"
target_file="$checkout_dir/Alderis/ColorPickerInnerViewController.swift"

if [ ! -f "$target_file" ]; then
	echo "Alderis patch target not found: $target_file" >&2
	exit 1
fi

if grep -q 'var selectedTab: ColorPickerTab {' "$target_file"; then
	exit 0
fi

if ! grep -q 'var tab: ColorPickerTab {' "$target_file"; then
	echo "Unexpected Alderis source layout in: $target_file" >&2
	exit 1
fi

perl -0pi -e 's/var tab: ColorPickerTab \{/var selectedTab: ColorPickerTab {/; s/tab = configuration\.initialTab/selectedTab = configuration.initialTab/' "$target_file"
