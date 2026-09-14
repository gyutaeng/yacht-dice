# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

YachtDice — a Godot 4.7 project (engine features: "4.7", "Forward Plus"). Currently just the initial engine
scaffold (`project.godot`, `icon.svg`); no scenes or scripts have been added yet.

## Non-default engine config (`project.godot`)

- 3D physics engine is set to **Jolt Physics**, not Godot's default (GodotPhysics).
- Windows rendering device driver is pinned to **d3d12** (`rendering_device/driver.windows`), not the default Vulkan.
- Rendering method is **Forward Plus**.
- Window stretch mode is `canvas_items` with `expand` aspect — keep new UI/camera logic aware of this scaling mode rather than assuming pixel-perfect or viewport-fixed sizing.

## Repo conventions

- Line endings are normalized to LF for all text files (`.gitattributes`).
- `.godot/`, `export.cfg`, and `export_presets.cfg` are gitignored — never commit generated editor cache or export presets.
