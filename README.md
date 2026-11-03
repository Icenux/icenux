# Icenux

Společný APT a RPM repozitář mých aplikací. Běží na GitHub Pages bez vlastního serveru.
Aplikace v něm zatím: [repo-doctor](https://github.com/Icenux/repo-doctor), [ccc](https://github.com/Icenux/ccc_TUI).

## Jak se používá

Balíček aplikace při instalaci repozitář Icenux sám přidá, takže nové verze přicházejí s běžnou
aktualizací systému (`sudo apt update && sudo apt upgrade`, `sudo dnf upgrade`).
Ručně (Debian/Ubuntu):

```sh
sudo curl -fsSL https://icenux.github.io/icenux/icenux.asc -o /usr/share/keyrings/icenux.asc
echo 'deb [signed-by=/usr/share/keyrings/icenux.asc] https://icenux.github.io/icenux/apt ./' \
  | sudo tee /etc/apt/sources.list.d/icenux.list
sudo apt update
```

## Ověření klíčů

Před přidáním zdroje si zkontroluj otisk klíče repozitáře. Stejný je na webu aplikací
(<https://icenux.github.io/apps/ccc/>) a v souboru `keys/fingerprint`, takže ho máš ze dvou nezávislých míst:

```
DED1 2904 B5BA E37D 0661  C626 A72C 50E3 F90C D644
```

```sh
gpg --show-keys --fingerprint /usr/share/keyrings/icenux.asc
```

Vydání jednotlivých aplikací podepisují vlastní klíče (`keys/<aplikace>.asc`); `SHA256SUMS.asc` v každém vydání
ověříš takto: `gpg --import keys/<aplikace>.asc && gpg --verify SHA256SUMS.asc SHA256SUMS`.

| Aplikace | Otisk podpisového klíče |
| --- | --- |
| ccc | `D5AE 3DC0 F062 9B5B 97E8  1C45 6A16 DF02 11F8 C1A5` |
| repo-doctor | `61CB 5447 85F6 CE13 3581  65CD DC0A DD39 ACA4 DB9A` |

## Jak to funguje

- `apps.txt` – seznam aplikací (`vlastník/repozitář` na GitHubu).
- `scripts/build-site.sh` – z nejnovějšího vydání každé aplikace vezme `.deb` a `.rpm`, ověří
  podpis `SHA256SUMS` klíčem z `keys/` a kontrolní součty balíčků, vyrobí metadata
  (`Packages`, `Release`, `repodata`) a podepíše je.
- `.github/workflows/publish.yml` – spouští build při změně v `main`, každou hodinu a ručně
  a výsledek nasadí na Pages. Při chybě (neplatný podpis, chybějící balíček) se nic nenasadí
  a stávající repozitář zůstane beze změny.
- Klíč Icenux podepisuje metadata repozitáře: soukromý je v secretu `RELEASE_SIGNING_KEY`, veřejný
  v `keys/icenux.asc` (otisk `keys/fingerprint`). Vydání aplikace musí mít `SHA256SUMS` podepsaný
  klíčem aplikace (`keys/<aplikace>.asc` a `keys/<aplikace>.fingerprint`).

V repozitáři je vždy jen **nejnovější verze** každé aplikace.

## Přidání aplikace

1. Vydání aplikace obsahuje `*.deb` a/nebo `*.rpm`, `SHA256SUMS` a `SHA256SUMS.asc` (podpis klíčem aplikace).
2. Veřejný klíč aplikace do `keys/<aplikace>.asc` a jeho otisk do `keys/<aplikace>.fingerprint`.
3. Řádek `vlastník/repozitář` do `apps.txt` (a za mezeru jméno balíčku, když se liší od jména repozitáře, např. `Icenux/ccc_TUI ccc`), commit do `main`.

GitHub vypne plánované workflow po 60 dnech bez aktivity v repozitáři. Pokud by hodinový běh
přestal, stačí ho znovu zapnout v záložce Actions, nebo spustit ručně.
