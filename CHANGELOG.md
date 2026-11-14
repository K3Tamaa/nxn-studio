# Changelog

**English** · [Français](CHANGELOG.fr.md)

## 1.5.0

Security and hardening pass:

- Homebrew installer pinned to a reviewed commit with SHA-256 verification, run from Terminal as the user (no admin prompt inside the app).
- Atomic app updates (`.new`/`.old` with rollback), bundle-identifier check, positional shell arguments, GitHub-only download hosts.
- Release scripts: confirmation before commit, no forced tags or pushes, no release overwrite, private key passed through stdin, `chmod 600` on the key file.
- IGDB credentials sent in the request body, Keychain write failures reported, image type/size limits.
- Process handling: whole process tree on quit, parallel pipe draining, 2 MB log cap, cancellation uses `Process.isRunning`.
- Git commands neutralise repository hooks and the file-system monitor; automatic home-folder repository detection removed.
- Python resolved to an absolute path; staging keeps extracted files and checks disk space on its own volume.
- Launcher restricted to `org.nxnative.<16 hex>` bundles, icons loaded on the main thread.
- Development flags compile into debug builds only.

## 1.4.0

- Full English interface (default), French switchable in Appearance; variable texts and PR states follow the language.
- English README, English-first repository.
- Remaining French strings in build, news, settings and launcher translated.

## 1.3.0

- **Launcher** tab: games already built on the Mac, with artwork, direct launch and adding from a folder.
- Automatic scan of `org.nxnative.*` bundles (Desktop, Downloads, Applications, build folders).

## 1.2.0

- Guided setup: Homebrew and the nxnative clone from the client.
- Manual selection of build contents (base, updates, DLC).
- Night / OLED / Day themes, five accent colours, floating dock navigation.
- Ed25519-signed app updates with SHA-256 verification.
- Diagnostics: Homebrew and git, copy report, re-check on every opening.
- IGDB: covers and banners, local cache, attribution.
- Artwork banner in the build screen, live build window.
- Cancellation now stops the whole process tree.
- Automated tests (`swift test`).

## 1.1.0

- nxnative updates from the client, What's new page, changelog after a pull.
- Single versioning (`VERSION`), DMG, dSYM, MIT licence.
