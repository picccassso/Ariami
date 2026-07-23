# FAQ

Answers here are all backed by the codebase — see the linked docs for the
underlying detail.

**Does Ariami CLI copy, move, or modify my music files?**
No. Setup and help text both say this explicitly
(`lib/services/cli_guidance.dart`), and the scanner only reads files to
extract tags/artwork (`ariami_core/lib/services/library/file_scanner.dart`).
Your music folder is stored as a path in `config.json`, never duplicated
into the Ariami data directory.

**What audio formats does the library scanner pick up?**
`.mp3 .m4a .mp4 .flac .wav .aiff .ogg .opus .wma .aac .alac`, checked
case-insensitively (`ariami_core`'s `FileScanner.supportedExtensions`). See
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#scan-finds-zero-tracks-or-far-fewer-than-expected)
for other reasons a scan might find fewer tracks than expected.

**Can I run it on a different port, or run more than one instance?**
Yes for the port (`ariami_cli start --port 9000`, or set it once and it's
saved). Running two instances on one machine needs two separate
`ARIAMI_DATA_DIR` values and two different ports — every CLI command reads
`ARIAMI_DATA_DIR` independently, so this works, but you must pass it
consistently to `start`/`stop`/`status`/`reset` for each instance. See
[`CLI_REFERENCE.md`](CLI_REFERENCE.md) and
[`CONFIGURATION.md`](CONFIGURATION.md).

**Where are passwords stored, and how?**
In `users.json` inside the Ariami data directory, hashed with `bcrypt`
(`ariami_core`'s `pubspec.yaml` dependency, used by the auth service). The
file and its parent directory are chmod'd `600`/`700` on Unix
(`ariami_core/lib/utils/secure_file_permissions.dart`); Windows relies on
per-user profile ACLs instead. `status` and startup output never print
passwords, tokens, or session/QR secrets — verified in
`ariami_core/lib/services/server/http_server_parts/middleware_and_metrics_part.dart`'s
redacting request logger and the CLI's own status/summary formatters.

**Can I expose Ariami to the public internet?**
The project's own guidance is: don't, directly. Keep it on LAN, Tailscale,
or another VPN. A deliberately public deployment must sit behind a
maintained HTTPS reverse proxy with `ARIAMI_PUBLIC_ORIGIN` set and the raw
HTTP port kept off the public internet — see the Security sections in
`../HEADLESS.md` and `../docker/DOCKER.md`, and
[`CONFIGURATION.md`](CONFIGURATION.md#networking-and-deployment).

**Does Ariami CLI need Docker?**
No — native binaries exist for Linux x64, Linux arm64 (including Raspberry
Pi), macOS arm64, and Windows x64. Docker is one deployment option among
several; see [`INSTALLATION.md`](INSTALLATION.md).

**What happens to my music folder if I run `reset`?**
Nothing, in either scope. The reset engine explicitly refuses to delete
anything that equals, contains, or is nested inside your configured music
folder path, regardless of scope (`ariami_core/lib/services/reset/
reset_service.dart`). See
[`CONFIGURATION.md`](CONFIGURATION.md#reset-scopes).

**How do I completely start over?**
`ariami_cli reset --factory` (interactive, type `RESET` to confirm) or
`ariami_cli reset --factory -y` (scripted, no prompt). This removes the
database, accounts, sessions, and caches, and disables start-on-boot, but
never touches your music files. See
[`CLI_REFERENCE.md`](CLI_REFERENCE.md#reset---setup--factory---yes-y).

**Is there a local GUI for the CLI, besides the browser dashboard?**
No — `ariami_cli` is purely headless; all setup and management happens
through the served web dashboard, reachable from any device on the network
(or `http://localhost:<port>` on the server itself). This monorepo has a
separate GUI desktop server package (`ariami_desktop`) for interactive
desktop use, but that's a different package from the one documented here.

**Why is my Raspberry Pi (or other ARM64 box) using lower concurrency
limits than I expected?**
Ariami tunes concurrency/cache limits down on anything it detects as a
Raspberry Pi — and conservatively, *any unrecognized ARM64 Linux host* gets
the same treatment. See
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#raspberry-pi--arm64-specifics)
and
[`CONFIGURATION.md`](CONFIGURATION.md#runtime-tuning-raspberry-pi--storage-detection).

**Where do I get more help than this?**
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) covers the verified failure
modes in depth; the project's source of truth beyond that is the code
itself, cited throughout these docs by file path.
