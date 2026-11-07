# Icenux

A shared APT, RPM and pacman (Arch) repository for my applications. It runs on GitHub Pages, no server of its own.
Apps in it so far: [repo-doctor](https://github.com/Icenux/repo-doctor), [ccc](https://github.com/Icenux/ccc_TUI),
[Live-M](https://github.com/Icenux/Live-M), [displays](https://github.com/Icenux/displays),
[scrv](https://github.com/Icenux/scrv), [Sway Desktop Stats](https://github.com/Icenux/sway_desktop_stats) and
[SGC Screensaver](https://github.com/Icenux/arch_SGC_screensaver).

## How to use it

An app's package adds the Icenux repository on install, so new versions arrive with the regular
system update (`sudo apt update && sudo apt upgrade`, `sudo dnf upgrade`).
Manually (Debian/Ubuntu):

```sh
sudo curl -fsSL https://icenux.github.io/icenux/icenux.asc -o /usr/share/keyrings/icenux.asc
echo 'deb [signed-by=/usr/share/keyrings/icenux.asc] https://icenux.github.io/icenux/apt ./' \
  | sudo tee /etc/apt/sources.list.d/icenux.list
sudo apt update
```

Then install an app with `sudo apt install <package>` (`repo-doctor`, `ccc`, `livem`, `displays`, `scrv`,
`sway-desktop-stats`, `sgc-screensaver`).

Arch Linux (pacman repository, signed):

```sh
sudo curl -fsSLo /tmp/icenux.asc https://icenux.github.io/icenux/icenux.asc
gpg --show-keys --fingerprint /tmp/icenux.asc   # must be DED1 2904 B5BA E37D 0661 C626 A72C 50E3 F90C D644
sudo pacman-key --add /tmp/icenux.asc
sudo pacman-key --lsign-key DED12904B5BAE37D0661C626A72C50E3F90CD644
sudo tee -a /etc/pacman.conf <<'EOF'
[icenux]
SigLevel = Required
Server = https://icenux.github.io/icenux/arch/$arch
EOF
sudo pacman -Sy livem
```

The fingerprint is also in "Verifying the keys" below. Every package and the database are signed with the Icenux key; a
package still gets in only through the signed `SHA256SUMS` of its release (see below).
Arch packages exist for repo-doctor, livem, displays, scrv, sway-desktop-stats and sgc-screensaver (not for ccc yet).

## Verifying the keys

Before adding the source, check the fingerprint of the repository key. It is the same on the apps' website
(<https://icenux.github.io/apps/ccc/>) and in the file `keys/fingerprint`, so you have it from two independent places:

```
DED1 2904 B5BA E37D 0661  C626 A72C 50E3 F90C D644
```

```sh
gpg --show-keys --fingerprint /usr/share/keyrings/icenux.asc
```

The releases of each app are signed with the app's own key (`keys/<app>.asc`); you verify the `SHA256SUMS.asc`
of a release like this: `gpg --import keys/<app>.asc && gpg --verify SHA256SUMS.asc SHA256SUMS`.

| App | Signing key fingerprint |
| --- | --- |
| ccc | `D5AE 3DC0 F062 9B5B 97E8  1C45 6A16 DF02 11F8 C1A5` |
| repo-doctor | `61CB 5447 85F6 CE13 3581  65CD DC0A DD39 ACA4 DB9A` |
| livem | `A4F1 F280 4AD3 0A96 4BB9  DA30 2330 7E96 9582 AFD9` |
| displays | `1231 9BE5 B7F6 48ED 8B5D  70E1 2D38 C9DC 9E61 6F6E` |
| scrv | `E0B8 3C1F 064A 94CC 10B9  36DD AF95 4553 54F6 1D8A` |
| sway-desktop-stats | `1CD3 AD5A 2F5E E290 642A  095A D0BB FC95 6E26 47C5` |
| sgc-screensaver | `9A97 F6C8 A2EC 7695 9187  4366 B9C5 9E43 05B9 CA8D` |

## How it works

- `apps.txt` – the list of apps (`owner/repository` on GitHub).
- `scripts/build-site.sh` – takes the `.deb`, `.rpm` and `.pkg.tar.zst` from the latest release of each app, verifies the
  signature of `SHA256SUMS` with the key from `keys/` and the checksums of the packages, builds the metadata
  (`Packages`, `Release`, `repodata`, and for Arch `icenux.db` in `arch/x86_64/`) and signs it (APT, RPM and pacman: every Arch package and `icenux.db` get a `.sig`).
- `.github/workflows/publish.yml` – runs the build on a change in `main`, every hour and manually,
  and deploys the result to Pages. On an error (invalid signature, missing package) nothing is deployed
  and the existing repository stays unchanged.
- The Icenux key signs the repository metadata: the private one is in the `RELEASE_SIGNING_KEY` secret, the public one
  in `keys/icenux.asc` (fingerprint `keys/fingerprint`). An app's release must have `SHA256SUMS` signed
  with the app's key (`keys/<app>.asc` and `keys/<app>.fingerprint`).

The repository always holds only the **latest version** of each app.

## Adding an app

1. The app's release contains `*.deb`, `*.rpm` and/or `*.pkg.tar.zst`, `SHA256SUMS` and `SHA256SUMS.asc` (signed with the app's key).
2. The app's public key goes to `keys/<app>.asc` and its fingerprint to `keys/<app>.fingerprint`.
3. Add a line `owner/repository` to `apps.txt` (and after a space the package name, when it differs from the repository name,
   e.g. `Icenux/ccc_TUI ccc`) and commit to `main`. Merge it only after the signed release exists, otherwise the build fails
   on the missing release and nothing is deployed.

GitHub disables scheduled workflows after 60 days without activity in the repository. If the hourly run
stops, just re-enable it in the Actions tab or run it manually.
