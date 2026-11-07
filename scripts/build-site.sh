#!/usr/bin/env bash
# Z nejnovějších vydání aplikací (apps.txt) vyrobí podepsaný APT a RPM repozitář a pacman repozitář
# (Arch) pro GitHub Pages do výstupní složky (výchozí dist/site):
#   apt/  – plochý repozitář (Packages, Release, InRelease, Release.gpg, pool/<aplikace>/*.deb)
#   rpm/  – repodata/ z createrepo_c + podepsaný repomd.xml.asc, <aplikace>/*.rpm
#   arch/x86_64/ – icenux.db (repo-add), *.pkg.tar.zst a podpisy (*.sig) klíčem Icenux: každý balíček i databáze
#                  (u uživatele SigLevel = Required po pacman-key --add / --lsign-key klíče Icenux)
#   icenux.asc – veřejný klíč repozitáře
#
# Klíče: metadata repozitáře podepisuje klíč Icenux (keys/icenux.asc, otisk keys/fingerprint;
# soukromý je v GNUPGHOME). Balíček se vezme jen tehdy, když sedí jeho SHA-256 v SHA256SUMS
# a ten je podepsaný klíčem té aplikace (keys/<aplikace>.asc, otisk keys/<aplikace>.fingerprint). Cokoli jiného build zastaví a
# stávající web zůstane beze změny. Podepsaný SHA256SUMS je seznam povolených souborů a balíček
# musí nést jméno aplikace a verzi odpovídající značce vydání.
#
# Volání: GH_TOKEN=<token> GNUPGHOME=<klíčenka s klíčem repozitáře> scripts/build-site.sh [VÝSTUP]
# Potřebuje gh, gpg, dpkg-deb, rpm, apt-ftparchive (apt-utils), createrepo_c a pro Arch repo-add
# (balíček pacman-package-manager), bsdtar (libarchive-tools) a zstd.
set -euo pipefail
cd "$(dirname "$0")/.."

site=${1:-dist/site}
fpr=$(tr -d '[:space:]' < keys/fingerprint)
sign=(gpg --batch --yes --local-user "$fpr")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

die() { echo "build-site: $*" >&2; exit 1; }


rm -rf "$site" && mkdir -p "$site/apt" "$site/rpm" "$site/arch/x86_64"
cp keys/icenux.asc "$site/icenux.asc"

apps=(); pkgs=()
while read -r app pkg _; do
    case "$app" in ''|'#'*) continue ;; esac
    apps+=("$app")
    pkgs+=("${pkg:-${app##*/}}")   # jméno balíčku (a klíčů): druhý sloupec, jinak jméno repozitáře
done < apps.txt
[ "${#apps[@]}" -gt 0 ] || die "apps.txt je prázdný"

summary=()
for i in "${!apps[@]}"; do
    app=${apps[$i]}
    name=${pkgs[$i]}
    dir=$work/$name
    mkdir -p "$dir"
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "$app: nepovolené jméno aplikace"
    tag=$(gh release view -R "$app" --json tagName --jq .tagName)
    [[ $tag =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "$app: nepovolená značka vydání '$tag'"
    ver=${tag#v}
    [ -f "keys/$name.asc" ] && [ -f "keys/$name.fingerprint" ] || die "$app: chybí keys/$name.asc nebo keys/$name.fingerprint"
    appfpr=$(tr -d '[:space:]' < "keys/$name.fingerprint")
    # klíč aplikace do samostatné klíčenky pro gpgv (soukromý klíč se nepoužije)
    gpg --dearmor < "keys/$name.asc" > "$work/$name.gpg"

    # 1) jen podepsaný seznam; teprve po ověření podpisu se stahují balíčky
    gh release download -R "$app" "$tag" -D "$dir" --pattern SHA256SUMS --pattern SHA256SUMS.asc
    status=$(gpgv --keyring "$work/$name.gpg" --status-fd 1 "$dir/SHA256SUMS.asc" "$dir/SHA256SUMS" 2>/dev/null) \
        || die "$app $tag: neplatný podpis SHA256SUMS"
    grep -q "^\[GNUPG:\] VALIDSIG $appfpr " <<< "$status" \
        || die "$app $tag: SHA256SUMS není podepsaný klíčem $appfpr"

    # 2) podepsaný seznam je seznam povolených souborů: stahují se přesně jeho .deb/.rpm/.pkg.tar.zst
    debs=(); rpms=(); pkgs_arch=()
    while read -r _ file; do
        file=${file#\*}
        case "$file" in *.deb|*.rpm|*.pkg.tar.zst) ;; *) continue ;; esac
        [[ $file =~ ^[A-Za-z0-9][A-Za-z0-9._+~-]*\.(deb|rpm|pkg\.tar\.zst)$ ]] || die "$app $tag: nepovolené jméno souboru '$file'"
        gh release download -R "$app" "$tag" -D "$dir" --pattern "$file"
        case "$file" in
            *.deb) debs+=("$dir/$file") ;;
            *.rpm) rpms+=("$dir/$file") ;;
            *) pkgs_arch+=("$dir/$file") ;;
        esac
    done < "$dir/SHA256SUMS"
    [ "${#debs[@]}" -gt 0 ] || [ "${#rpms[@]}" -gt 0 ] || [ "${#pkgs_arch[@]}" -gt 0 ] \
        || die "$app $tag: SHA256SUMS neuvádí .deb, .rpm ani .pkg.tar.zst"
    (cd "$dir" && grep -E '\.(deb|rpm|pkg\.tar\.zst)$' SHA256SUMS | sha256sum -c --quiet -) \
        || die "$app $tag: kontrolní součet balíčku nesedí"

    # 3) podepsaný obsah musí patřit právě této aplikaci a verzi (proti podstrčení starého balíčku)
    for f in "${debs[@]}"; do
        [ "$(dpkg-deb -f "$f" Package)" = "$name" ] || die "$f: balíček není '$name'"
        [ "$(dpkg-deb -f "$f" Version | sed 's/-[^-]*$//')" = "$ver" ] || die "$f: verze neodpovídá značce $tag"
    done
    for f in "${rpms[@]}"; do
        [ "$(rpm -qp --qf '%{NAME}' "$f")" = "$name" ] || die "$f: balíček není '$name'"
        [ "$(rpm -qp --qf '%{VERSION}' "$f")" = "$ver" ] || die "$f: verze neodpovídá značce $tag"
    done

    for f in "${pkgs_arch[@]}"; do
        info=$(bsdtar -xOf "$f" .PKGINFO) || die "$f: nejde přečíst .PKGINFO"
        [ "$(sed -n 's/^pkgname = //p' <<< "$info")" = "$name" ] || die "$f: balíček není '$name'"
        [ "$(sed -n 's/^pkgver = //p' <<< "$info" | sed 's/-[^-]*$//')" = "$ver" ] || die "$f: verze neodpovídá značce $tag"
        case "$(sed -n 's/^arch = //p' <<< "$info")" in any|x86_64) ;; *) die "$f: nepodporovaná architektura" ;; esac
    done

    if [ "${#debs[@]}" -gt 0 ]; then
        mkdir -p "$site/apt/pool/$name"
        cp "${debs[@]}" "$site/apt/pool/$name/"
    fi
    if [ "${#rpms[@]}" -gt 0 ]; then
        mkdir -p "$site/rpm/$name"
        cp "${rpms[@]}" "$site/rpm/$name/"
    fi
    if [ "${#pkgs_arch[@]}" -gt 0 ]; then
        cp "${pkgs_arch[@]}" "$site/arch/x86_64/"
    fi
    summary+=("$name $tag")
    echo "build-site: $app $tag ověřeno (${#debs[@]}× deb, ${#rpms[@]}× rpm, ${#pkgs_arch[@]}× pkg.tar.zst)"
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

# Arch (pacman): databáze bez podpisu; GitHub Pages nezná symlinky, takže icenux.db a icenux.files jsou kopie
(
    cd "$site/arch/x86_64"
    if compgen -G "*.pkg.tar.zst" > /dev/null; then
        # balíčky se podepisují před repo-add (do databáze se pak zapíše i podpis); podpis je binární (*.sig), jak chce pacman
        for f in ./*.pkg.tar.zst; do "${sign[@]}" --detach-sign --output "$f.sig" "$f"; done
        repo-add --quiet --nocolor icenux.db.tar.gz ./*.pkg.tar.zst
        rm -f ./*.old
        for f in icenux.db icenux.files; do
            "${sign[@]}" --detach-sign --output "$f.tar.gz.sig" "$f.tar.gz"
            cp --remove-destination "$f.tar.gz" "$f"
            cp --remove-destination "$f.tar.gz.sig" "$f.sig"
        done
    else
        cd .. && rmdir x86_64 && cd .. && rmdir arch
    fi
)

{
    echo '<!doctype html><meta charset="utf-8"><title>Icenux – balíčkové repozitáře</title>'
    echo '<p>APT, RPM a pacman repozitář <a href="https://github.com/Icenux/icenux">Icenux</a>. Aplikace:</p><ul>'
    for item in "${summary[@]}"; do echo "<li>${item}</li>"; done
    echo '</ul>'
} > "$site/index.html"
touch "$site/.nojekyll"
find "$site" -type f | sort
