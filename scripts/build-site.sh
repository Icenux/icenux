#!/usr/bin/env bash
# Z nejnovějších vydání aplikací (apps.txt) vyrobí podepsaný APT a RPM repozitář pro
# GitHub Pages do výstupní složky (výchozí dist/site):
#   apt/  – plochý repozitář (Packages, Release, InRelease, Release.gpg, pool/<aplikace>/*.deb)
#   rpm/  – repodata/ z createrepo_c + podepsaný repomd.xml.asc, <aplikace>/*.rpm
#   icenux.asc – veřejný klíč repozitáře
#
# Balíček se vezme jen tehdy, když sedí jeho SHA-256 v SHA256SUMS a ten je podepsaný
# klíčem z keys/icenux.asc (otisk keys/fingerprint). Cokoli jiného build zastaví a
# stávající web zůstane beze změny.
#
# Volání: GH_TOKEN=<token> GNUPGHOME=<klíčenka s klíčem repozitáře> scripts/build-site.sh [VÝSTUP]
# Potřebuje gh, gpg, apt-ftparchive (apt-utils) a createrepo_c.
set -euo pipefail
cd "$(dirname "$0")/.."

site=${1:-dist/site}
fpr=$(tr -d '[:space:]' < keys/fingerprint)
sign=(gpg --batch --yes --local-user "$fpr")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

die() { echo "build-site: $*" >&2; exit 1; }

# Veřejný klíč pro ověřování podpisů vydání (samostatná klíčenka, nepoužívá soukromý klíč).
gpg --dearmor < keys/icenux.asc > "$work/pub.gpg"

rm -rf "$site" && mkdir -p "$site/apt" "$site/rpm"
cp keys/icenux.asc "$site/icenux.asc"

apps=()
while read -r app _; do
    case "$app" in ''|'#'*) continue ;; esac
    apps+=("$app")
done < apps.txt
[ "${#apps[@]}" -gt 0 ] || die "apps.txt je prázdný"

summary=()
for app in "${apps[@]}"; do
    name=${app##*/}
    dir=$work/$name
    mkdir -p "$dir"
    tag=$(gh release view -R "$app" --json tagName --jq .tagName)
    gh release download -R "$app" "$tag" -D "$dir" \
        --pattern '*.deb' --pattern '*.rpm' --pattern SHA256SUMS --pattern SHA256SUMS.asc

    # podpis SHA256SUMS: platný a přesně od klíče Icenux
    status=$(gpgv --keyring "$work/pub.gpg" --status-fd 1 "$dir/SHA256SUMS.asc" "$dir/SHA256SUMS" 2>/dev/null) \
        || die "$app $tag: neplatný podpis SHA256SUMS"
    grep -q "^\[GNUPG:\] VALIDSIG $fpr " <<< "$status" \
        || die "$app $tag: SHA256SUMS není podepsaný klíčem $fpr"

    # kontrolní součty jen u balíčků, které jsme stáhli
    (cd "$dir" && grep -E '\.(deb|rpm)$' SHA256SUMS | sha256sum -c --quiet -) \
        || die "$app $tag: kontrolní součet balíčku nesedí"

    shopt -s nullglob
    debs=("$dir"/*.deb)
    rpms=("$dir"/*.rpm)
    shopt -u nullglob
    [ "${#debs[@]}" -gt 0 ] || [ "${#rpms[@]}" -gt 0 ] || die "$app $tag: vydání neobsahuje .deb ani .rpm"
    if [ "${#debs[@]}" -gt 0 ]; then
        mkdir -p "$site/apt/pool/$name"
        cp "${debs[@]}" "$site/apt/pool/$name/"
    fi
    if [ "${#rpms[@]}" -gt 0 ]; then
        mkdir -p "$site/rpm/$name"
        cp "${rpms[@]}" "$site/rpm/$name/"
    fi
    summary+=("$name $tag")
    echo "build-site: $app $tag ověřeno (${#debs[@]}× deb, ${#rpms[@]}× rpm)"
done

# APT
(
    cd "$site/apt"
    if [ -d pool ]; then
        apt-ftparchive packages . > Packages
    else
        : > Packages
    fi
    gzip -9kn Packages
    apt-ftparchive \
        -o APT::FTPArchive::Release::Origin=Icenux \
        -o APT::FTPArchive::Release::Label=Icenux \
        -o APT::FTPArchive::Release::Architectures=amd64 \
        release . > Release
    "${sign[@]}" --clearsign --output InRelease Release
    "${sign[@]}" --armor --detach-sign --output Release.gpg Release
)

# RPM
createrepo_c --quiet "$site/rpm"
"${sign[@]}" --armor --detach-sign --output "$site/rpm/repodata/repomd.xml.asc" \
    "$site/rpm/repodata/repomd.xml"

{
    echo '<!doctype html><meta charset="utf-8"><title>Icenux – balíčkové repozitáře</title>'
    echo '<p>APT a RPM repozitář <a href="https://github.com/Luquas95/icenux">Icenux</a>. Aplikace:</p><ul>'
    for item in "${summary[@]}"; do echo "<li>${item}</li>"; done
    echo '</ul>'
} > "$site/index.html"
touch "$site/.nojekyll"
find "$site" -type f | sort
