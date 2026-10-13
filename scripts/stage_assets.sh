#!/usr/bin/env bash
# Stage assets/ into build/site/ in the layout published at assets.bensoyka.com.
#
# Everything outside assets/photo/ is copied verbatim. Photos are stored as
# dated versions, assets/photo/<YYYY-MM>-<name>.<ext>, and fan out to:
#
#   photo/<name>/<YYYY-MM>.<ext>   every version, including the newest
#   photo/<name>.<ext>             the newest version only
#
# so existing undated URLs keep serving the latest photo while older versions
# stay addressable. Resolving "latest" here rather than in the transform Lambda
# keeps the Lambda a plain key lookup with no s3:ListBucket.
#
# Written for bash 3.2 (no associative arrays) so it also runs on stock macOS.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$root_dir/assets"
out_dir="$root_dir/build/site"

rm -rf "$out_dir"
mkdir -p "$out_dir"

cp -Rp "$src_dir/." "$out_dir/"
rm -rf "$out_dir/photo"
mkdir -p "$out_dir/photo"

# Extensions the transform Lambda can read a source from.
name_re='^([0-9]{4}-(0[1-9]|1[0-2]))-([a-z0-9]+(-[a-z0-9]+)*)\.(jpg|jpeg|png|webp|avif)$'

status=0

# Newest first, so the first version seen for each name is the one that
# becomes photo/<name>.<ext>. YYYY-MM prefixes sort chronologically as text.
while IFS= read -r filename; do
    # The extension is lowercased because S3 keys are case-sensitive and the
    # Lambda only ever looks up lowercase extensions -- a .JPG would 404.
    lower="$(printf '%s' "$filename" | tr '[:upper:]' '[:lower:]')"

    if [[ ! "$lower" =~ $name_re ]]; then
        echo "error: assets/photo/$filename doesn't match <YYYY-MM>-<name>.<ext>" >&2
        status=1
        continue
    fi

    date="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[3]}"
    ext="${BASH_REMATCH[5]}"
    [[ "$ext" == "jpeg" ]] && ext="jpg"

    if compgen -G "$out_dir/photo/$name/$date.*" >/dev/null; then
        echo "error: more than one $date version of '$name' in assets/photo/" >&2
        status=1
        continue
    fi

    mkdir -p "$out_dir/photo/$name"
    cp -p "$src_dir/photo/$filename" "$out_dir/photo/$name/$date.$ext"

    if ! compgen -G "$out_dir/photo/$name.*" >/dev/null; then
        cp -p "$src_dir/photo/$filename" "$out_dir/photo/$name.$ext"
        echo "photo/$name.$ext <- $filename"
    fi
done < <(find "$src_dir/photo" -mindepth 1 -maxdepth 1 -type f ! -name '.*' -exec basename {} \; | sort -r)

if find "$src_dir/photo" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
    echo "error: assets/photo/ must be flat; versions are named, not nested" >&2
    status=1
fi

exit "$status"
