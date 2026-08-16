# Icarus Craft Tracker Mod

A sleek, lightweight, in-game Crafting Recipe Tracker HUD for **ICARUS**.

Pin any recipe from crafting benches, furnaces, or your character crafting menu directly to your HUD to track required materials live as you explore and gather resources.

---

## Features

- **Middle-Mouse-Button (MMB) Pinning**: Click any recipe in a bench or inventory and press **Middle Mouse Button** to pin it to your screen.
- **Live Inventory Tracking**: Tracks your materials in real time with exact 1:1 counts (eliminating duplicate counts).
- **Dynamic Progress & Status**:
  - Automatically displays checkmarks `[✓]` when you have enough resources.
  - Highlights missing ingredients with `[✗]`.
  - Shows `READY TO CRAFT!` when all ingredients are collected.
- **Elevated Frosted Glass HUD**: Top-center placement with a clean, unobtrusive visual design that never obstructs your crafting window or inventory grid.
- **Auto-Collapsing Rows**: Dynamically resizes to fit recipes with 1 to 6 ingredients, keeping the HUD compact and clean.
- **High Performance & Stability**: Built for long multiplayer and solo sessions with zero frame drops or memory leaks.

---

## Installation

### Prerequisites
- **ICARUS** (DirectX 11 recommended)
- **[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)** (Standard Unreal Engine 4 mod loader)

### Install Steps
1. Download the latest release from the repository.
2. Copy the `Icarus` folder directly into your game installation directory:
   - `Steam\steamapps\common\Icarus\`
3. Launch the game, open any crafting bench, and press **Middle Mouse Button (MMB)** on any recipe!

---

## Controls

| Action | Control |
|---|---|
| **Pin Recipe** | Click recipe in crafting bench -> Press **Middle Mouse Button (MMB)** |
| **Unpin / Dismiss HUD** | Press **Middle Mouse Button (MMB)** on the recipe again |

---

## File Structure

```text
Icarus/
├── Binaries/Win64/Mods/IcarusCraftTracker/
│   ├── Scripts/
│   │   ├── main.lua                # Master Lua tracker engine (v42.0)
│   │   ├── ItemDisplayNames.lua    # Localized item name mappings
│   │   ├── Recipes_Chunk1..6.lua   # 1,400+ recipe database
│   │   └── AllRecipes.lua
│   └── enabled.txt
└── Content/Paks/LogicMods/
    └── IcarusCraftTracker.pak      # Custom UMG HUD Widget
```

---

## License
This mod is created for the Icarus community. Feel free to modify and adapt.
