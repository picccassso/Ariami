# FAQ

Each answer is backed by the codebase, with links to the docs that cover the
underlying detail.

**Does Ariami CLI copy, move, or modify my music files?**
No. The scanner reads audio files to extract tags and artwork, and that is
all (`ariami_core/lib/services/library/file_scanner.dart`). Setup and help
text both say this explicitly (`lib/services/cli_guidance.dart`). Your music
folder is stored as a path in `config.json` and is never copied into the
Ariami data directory.

**What audio formats does the library scanner pick up?**
`.mp3 .m4a .mp4 .flac .wav .aiff .ogg .opus .wma .aac .alac`, checked
case-insensitively (`ariami_core`'s `FileScanner.supportedExtensions`). See
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#scan-finds-zero-tracks-or-far-fewer-than-expected)
for other reasons a scan might find fewer tracks than expected.

**Can I run it on a different port, or run more than one instance?**
Yes for the port. On a first run, `ariami_cli start --port 9000` (or
`ARIAMI_PORT=9000`) picks the port and saves it; later starts reuse the saved
value, so to change it on an existing install, stop the server and edit
`server_port` in `config.json`. Running two instances on one machine needs
two separate `ARIAMI_DATA_DIR` values and two different ports. Every CLI
command reads `ARIAMI_DATA_DIR` independently, so this works, but you must
pass it consistently to `start`/`stop`/`status`/`reset` for each instance.
See [`CLI_REFERENCE.md`](CLI_REFERENCE.md) and
[`CONFIGURATION.md`](CONFIGURATION.md).

**Where are passwords stored, and how?**
In `users.json` inside the Ariami data directory, hashed with `bcrypt`
(`ariami_core`'s `pubspec.yaml` dependency, used by the auth service). The
file and its parent directory are chmod'd `600`/`700` on Unix
(`ariami_core/lib/utils/secure_file_permissions.dart`); Windows relies on
per-user profile ACLs instead. `status` and startup output never print
passwords, tokens, or session/QR secrets, which is verified in
`ariami_core/lib/services/server/http_server_parts/middleware_and_metrics_part.dart`'s
redacting request logger and the CLI's own status/summary formatters.

**Can I expose Ariami to the public internet?**
Keep it on LAN, Tailscale, or another VPN. If you deliberately deploy it
publicly, put a maintained HTTPS reverse proxy in front, set
`ARIAMI_PUBLIC_ORIGIN` to the proxy's origin, and keep the raw HTTP port off
the public internet. See the Security sections in `../HEADLESS.md` and
`../docker/DOCKER.md`, and
[`CONFIGURATION.md`](CONFIGURATION.md#networking-and-deployment).

**Does Ariami CLI need Docker?**
Docker is one deployment option among several. Native release zips are built
for Linux x64, Linux arm64 (including Raspberry Pi), macOS arm64, and
Windows x64; see [`INSTALLATION.md`](INSTALLATION.md).

**What happens to my music folder if I run `reset`?**
Your music stays untouched in either scope. The reset engine explicitly
refuses to delete anything that equals, contains, or is nested inside your
configured music folder path, regardless of scope
(`ariami_core/lib/services/reset/reset_service.dart`).
See [`CONFIGURATION.md`](CONFIGURATION.md#reset-scopes).

**How do I completely start over?**
`ariami_cli reset --factory` (interactive, type `RESET` to confirm) or
`ariami_cli reset --factory -y` (scripted, no prompt). This removes the
database, accounts, sessions, and caches, and disables start-on-boot. It
never touches your music files. See
[`CLI_REFERENCE.md`](CLI_REFERENCE.md#reset---setup----factory---yes-y).

**Is there a local GUI for the CLI, besides the browser dashboard?**
`ariami_cli` is purely headless. All setup and management happens through the
served web dashboard, reachable from any device on the network (or
`http://localhost:<port>` on the server itself). This monorepo has a
separate GUI desktop server package (`ariami_desktop`) for interactive
desktop use, but that's a different package from the one documented here.

**Why is my Raspberry Pi (or other ARM64 box) using lower concurrency
limits than I expected?**
Ariami tunes concurrency and cache limits down on anything it detects as a
Raspberry Pi, and conservatively, any unrecognised ARM64 Linux host gets the
same treatment. See
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#raspberry-pi--arm64-specifics)
and
[`CONFIGURATION.md`](CONFIGURATION.md#runtime-tuning-raspberry-pi--storage-detection).

**Where do I get more help than this?**
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) covers the verified failure
modes in depth. Beyond that, the project's source of truth is the code
itself, cited throughout these docs by file path.
