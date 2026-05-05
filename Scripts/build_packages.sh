#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="$repo_root/out"
packages_dir="$repo_root/packages"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/sileo-packages.XXXXXX")"
app_name="Sileo.app"

trap 'rm -rf "$work_dir"' EXIT

log() {
    printf '[build_packages] %s\n' "$*" >&2
}

fail() {
    printf '[build_packages] ERROR: %s\n' "$*" >&2
    exit 1
}

first_deb_in_packages() {
    find "$packages_dir" -maxdepth 1 -type f -name '*.deb' -print -quit
}

deb_field() {
    local deb="$1"
    local field="$2"
    dpkg-deb -f "$deb" "$field"
}

build_make_package() {
    local platform="$1"

    rm -rf "$packages_dir"
    mkdir -p "$out_dir"

    log "构建 ${platform} 包"
    make -C "$repo_root" clean package SILEO_PLATFORM="$platform" >&2

    local deb_path
    deb_path="$(first_deb_in_packages)"
    [ -n "$deb_path" ] || fail "未找到 ${platform} 构建产物"

    local output_path="$out_dir/$(basename "$deb_path")"
    cp -f "$deb_path" "$output_path"
    printf '%s\n' "$output_path"
}

rewrite_roothide_script_paths() {
    local script_path="$1"
    [ -f "$script_path" ] || return 0

    perl -0pi -e '
        s#/var/jb/Applications/#/Applications/#g;
        s#/var/jb/Library/#/Library/#g;
        s#/var/jb/usr/#/usr/#g;
        s#/var/jb/etc/#/etc/#g;
        s#/var/jb/bin/#/bin/#g;
        s#/var/jb/sbin/#/sbin/#g;
        s#/var/jb/System/#/System/#g;
        s#/var/jb/private/#/private/#g;
    ' "$script_path"
}

convert_rootless_to_roothide() {
    local rootless_deb="$1"
    local unpack_dir="$work_dir/rootless-unpack"
    local roothide_dir="$work_dir/roothide-stage"

    rm -rf "$unpack_dir" "$roothide_dir"
    mkdir -p "$roothide_dir"

    log "从 rootless 包转换 roothide"
    dpkg-deb -R "$rootless_deb" "$unpack_dir"

    [ -d "$unpack_dir/DEBIAN" ] || fail "rootless 包缺少 DEBIAN"
    [ -d "$unpack_dir/var/jb" ] || fail "rootless 包缺少 var/jb 根目录"

    mv "$unpack_dir/DEBIAN" "$roothide_dir/DEBIAN"

    while IFS= read -r path; do
        mv "$path" "$roothide_dir/"
    done < <(find "$unpack_dir/var/jb" -mindepth 1 -maxdepth 1 | sort)

    rm -rf "$unpack_dir/var"

    if find "$unpack_dir" -mindepth 1 -maxdepth 1 | grep -q .; then
        mkdir -p "$roothide_dir/rootfs"
        while IFS= read -r path; do
            mv "$path" "$roothide_dir/rootfs/"
        done < <(find "$unpack_dir" -mindepth 1 -maxdepth 1 | sort)
    fi

    local control_path="$roothide_dir/DEBIAN/control"
    [ -f "$control_path" ] || fail "roothide 转换时缺少 control"
    perl -0pi -e 's/^Architecture:\s+\S+$/Architecture: iphoneos-arm64e/m' "$control_path"

    local script_name
    for script_name in preinst postinst prerm postrm; do
        rewrite_roothide_script_paths "$roothide_dir/DEBIAN/$script_name"
    done

    local package_id version output_path
    package_id="$(deb_field "$rootless_deb" Package)"
    version="$(deb_field "$rootless_deb" Version)"
    output_path="$out_dir/${package_id}_${version}_iphoneos-arm64e.deb"
    dpkg-deb --root-owner-group -b "$roothide_dir" "$output_path" >/dev/null
    printf '%s\n' "$output_path"
}

verify_app_package() {
    local deb_path="$1"
    local expected_arch="$2"
    local expected_app_path="$3"
    local forbid_rootless_layout="$4"
    local unpack_dir="$work_dir/verify-$(basename "$deb_path" .deb)"

    rm -rf "$unpack_dir"
    dpkg-deb -R "$deb_path" "$unpack_dir"

    local actual_arch
    actual_arch="$(deb_field "$deb_path" Architecture)"
    [ "$actual_arch" = "$expected_arch" ] || fail "$(basename "$deb_path") 架构不符: $actual_arch"

    [ -d "$unpack_dir/$expected_app_path" ] || fail "$(basename "$deb_path") 缺少 $expected_app_path"

    if [ "$forbid_rootless_layout" = "1" ] && [ -e "$unpack_dir/var/jb" ]; then
        fail "$(basename "$deb_path") 不应保留 var/jb 布局"
    fi
}

main() {
    mkdir -p "$out_dir"

    local rootful_deb rootless_deb roothide_deb
    rootful_deb="$(build_make_package iphoneos-arm)"
    verify_app_package "$rootful_deb" "iphoneos-arm" "Applications/$app_name" "1"

    rootless_deb="$(build_make_package iphoneos-arm64)"
    verify_app_package "$rootless_deb" "iphoneos-arm64" "var/jb/Applications/$app_name" "0"

    roothide_deb="$(convert_rootless_to_roothide "$rootless_deb")"
    verify_app_package "$roothide_deb" "iphoneos-arm64e" "Applications/$app_name" "1"

    log "构建完成"
    printf '%s\n%s\n%s\n' "$rootful_deb" "$rootless_deb" "$roothide_deb"
}

main "$@"
