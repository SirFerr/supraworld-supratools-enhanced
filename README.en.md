# SupraTools Enhanced for Supraworld

[Русский](README.md) | English

A community modification of **[SupraTools 1.0.3 by joric](https://github.com/joric/SupraTools)**, adding player protection, item search and glowing world beacons. Original SupraTools features are retained. joric is not responsible for these additions.

## Features

- Unified help and search panel: **Alt+H**.
- Categories: Solvers' Guide pages, secrets, coins, presents and ability eggs.
- Collected pages, opened eggs and collected egg rewards are filtered from search and the minimap. Hidden actors and rewards observed alive and subsequently destroyed are also filtered.
- Secret markers within 1.5 metres of an egg are suppressed to avoid duplicate egg entries. This distance rule can also suppress an unrelated secret very close to an egg.
- Real world mesh beacons approximately **10 km tall**, with category colours and emissive materials. No collision, physics or shadows.
- Distance labels with shadows and overlap handling.
- Local player protection from ordinary damage, enabled by default.
- Self-contained installer with UE4SS, file verification, backups and rollback.

| Category | Colour |
|---|---|
| Pages | Cyan |
| Secrets | Green |
| Coins | Gold |
| Presents | Pink |
| Ability eggs | Purple |

Ability search covers `ShopEgg_C` and `ChocolateEgg_C`, rather than every quest reward or upgrade. Filtering uses actor and reward state, not a full inventory ownership lookup. A reward destroyed before this session's scan may not be identifiable unless the egg retains its collected/opened state. Only loaded objects are searchable; counts do not represent every remaining item in the game.

## Installation

1. Close Supraworld.
2. Download **[Install-SupraTools.ps1](https://github.com/SirFerr/supraworld-supratools-enhanced/raw/refs/heads/main/Install-SupraTools.ps1)**, or use the [latest release](https://github.com/SirFerr/supraworld-supratools-enhanced/releases/latest).
3. Open PowerShell in the download folder and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-SupraTools.ps1
```

For a custom Steam library:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-SupraTools.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Supraworld"
```

Verify the embedded package without installing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-SupraTools.ps1 -VerifyOnly
```

Backups are created under `Supraworld\Binaries\Win64\SupraTools-backups`. To roll back, close the game and run the backup's `Restore.ps1`. Existing UE4SS settings and other mods are preserved. Installation stops if a different `dwmapi.dll` loader is detected. The installer does not launch the game or change saves, DLSS or MFG Bridge.

## Controls

| Shortcut | Action |
|---|---|
| Alt+H | Toggle the unified panel |
| Alt+Left | Switch help/search tabs |
| Alt+Up / Alt+Down | Select a search setting |
| Alt+Right | Change the selected setting |
| Alt+B | Toggle world beacons |
| Alt+M | Toggle the SupraTools minimap |
| Alt+K | Toggle player protection |
| F10 | Open the console |

Beacons start disabled. The menu offers category selection, 50 / 200 / 500 / 1000 metre range and an 8 / 16 / 24 beacon limit. Search preferences are stored in `%LOCALAPPDATA%\Supraworld\SupraSearch.ini`.

Console commands include `supra_search`, `supra_search beams`, `supra_search abilities`, `supra_search radius 1000` and `supra_search status`.

## Compatibility and validation

Target: **Supraworld build 12678, Unreal Engine 5.7.4, Windows / Steam**. Game updates may change object classes and UE4SS behaviour. Protection handles ordinary damage; scripted death and world boundaries may bypass it.

See [VALIDATION.md](VALIDATION.md) for the scope of testing. Lua model tests and installer checks do not prove in-game behaviour. The latest filtering changes have not been tested in the game.

## Source and packaging

The modified source is in `SupraTools/Scripts`. With UE4SS already installed, copy `SupraTools` into `ue4ss/Mods` and enable it in `mods.txt`.

Build the installer with Python 3 from a prepared game folder containing UE4SS and these sources:

```powershell
python tools/build_installer.py --win64 "D:\SteamLibrary\steamapps\common\Supraworld\Supraworld\Binaries\Win64" --output Install-SupraTools.ps1
```

## Credits and licence

Based on **joric / [SupraTools](https://github.com/joric/SupraTools)**, MIT, copyright 2025 joric. Additions and packaging were prepared with Codex. Runtime: **[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)**; its licence is included in the installer. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
