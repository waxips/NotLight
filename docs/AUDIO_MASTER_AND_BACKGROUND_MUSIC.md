<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Application Audio and Background Music

This document describes the NotLight application-level audio contract. It covers the master output control, bundled background music, Resource Library audio used as background music, and automatic ducking while foreground media is playing.

## Master output

NotLight stores an application master-audio enabled flag and a normalized master volume. The application audio service applies those settings to Godot's `Master` audio bus. Setting the master output to disabled, or effectively to zero, mutes the bus.

The settings UI applies level changes interactively so the user can hear the result while moving a slider. Audio sliders are configured not to react to mouse-wheel scrolling accidentally.

## Background music sources

Background music can come from either of these sources:

1. **Bundled tracks** under `res://assets/audio/background/`. Supported bundled extensions are `.ogg`, `.mp3`, and `.wav`.
2. **Audio assets in the Resource Library.** The selected Library item is stored by its stable asset ID, not by an arbitrary external filesystem path.

When no explicit selection is stored, the service may choose the first available bundled track and then fall back to an available Library audio asset.

Bundled audio intended for official distribution must have documented provenance, licensing, attribution, and any required change statement before it is added to a release. See `THIRD_PARTY_NOTICES.md`, `THIRD_PARTY_COMPONENTS.json`, and `RELEASE_COMPLIANCE.md`.

## Library reference protection

When a Resource Library audio asset is selected for background music, NotLight registers an application feature reference for it. This prevents cleanup code from treating an actively configured background track as an unreferenced asset. Switching away from the asset releases that feature reference.

## Foreground-media ducking

Background music is automatically ducked while audible foreground media is active, including video, Library audio playback, and voice-note playback. Ducking uses separate attack and release rates so transitions are quick without producing an abrupt return to full background volume.

## Settings and persistence

The relevant settings include:

- master audio enabled state and volume;
- background-music enabled state and volume;
- bundled background track path, when a bundled track is selected;
- Resource Library asset ID, when a Library track is selected.

Legacy settings are migrated by `AppSettingsStore` so newer selection fields can be introduced without silently discarding older preferences.

## Release hygiene

`.godot/` is generated editor/import cache and is never source-release material. A clean source archive must omit it entirely. The release compliance validator also rejects undocumented audio files and known unwanted media names.

The two background tracks currently approved for redistribution are documented in `assets/audio/background/README_RU.txt` and `THIRD_PARTY_NOTICES.md`; their exact local hashes are recorded in `THIRD_PARTY_COMPONENTS.json`.
