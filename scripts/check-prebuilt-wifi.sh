#!/bin/sh
set -eu
export LC_ALL=C
target=${1:?target kernel required}
sha256sum -c prebuilt/aic8800.sha256
for name in aic_load_fw aic8800_fdrv; do
    module="prebuilt/$target/$name.ko"
    version=$(modinfo -F vermagic "$module")
    case "$version" in
        "$target "*) ;;
        *) echo "Wrong kernel ABI: $module: $version" >&2; exit 1 ;;
    esac
    readelf -h "$module" | grep -Eq 'Machine:.*AArch64' || {
        echo "Not an ARM64 module: $module" >&2; exit 1;
    }
done
