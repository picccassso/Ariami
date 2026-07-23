# CLI Reference

Every command, flag, and exit code below is taken directly from the argument
parser in `bin/ariami_cli.dart` and the command classes in `lib/commands/`.
Nothing here is inferred or planned — if a flag isn't listed, it doesn't
exist.

## Global usage

```
ariami_cli <command> [options]
```

Global flags (parsed by the top-level `ArgParser` in `bin/ariami_cli.dart`):

| Flag | Abbr | Meaning |
| --- | --- | --- |
| `--help` | `-h` | Show the built-in help/usage text and exit. |
| `--version` | `-v` | Print `Ariami CLI version <version>` (from `kAriamiVersion`) and exit. |
| `--port <port>` | `-p` | Server port. Default `8080`. |
| `--host <address>` | | HTTP bind address. Default `0.0.0.0`. |
| `--no-browser` | | During setup, print URLs and never auto-open a browser. |
| `--verbose` | | Show stack traces and extra debug output for startup failures. |
| `--server-mode` | | **Hidden/internal.** Runs the HTTP server in the foreground for a supervisor (systemd, Docker). Not meant to be run by hand outside a service unit. |
| `--setup` | | Used with `reset`: setup/config only. |
| `--factory` | | Used with `reset`: factory reset all data. |
| `--yes` | `-y` | Used with `reset`: skip the confirmation prompt. |

Running with no command prints `Error: No command specified.` to stderr, the
usage text, and exits `2`. An unknown command prints
`Error: Unknown command "<command>"` the same way.

## Commands

### `start`

```
ariami_cli start [--port|-p <port>] [--host <address>] [--no-browser] [--verbose]
```

- First run (setup not yet complete): runs the server **in the foreground**.
  On an interactive terminal (and not piped from `/dev/null`), it first asks
  `Start Ariami automatically on boot (after restart, etc.)? [y/N]:` — a
  non-interactive session (no TTY, or stdin at EOF) skips the prompt and
  tells you to run `ariami_cli autostart enable` later
  (`lib/commands/start_command.dart`). It then prints the setup URLs
  (`This machine`, `Same network`, `Tailscale` when detected) and opens a
  browser unless `--no-browser` was passed. When the web wizard finishes,
  the process **transitions itself into a background daemon** automatically
  and the foreground process exits.
- Subsequent runs (setup already complete): starts the server directly **in
  the background** and returns control of the terminal immediately, printing
  a startup summary (PID, dashboard/LAN/Tailscale URLs, data dir, music
  folder, auth state).
- If the server is already running, prints
  `Ariami CLI server is already running.` and returns without error.
- `--port`/`-p` only matters before a port has been saved (first run, or an
  explicit override); afterwards the saved port from `config.json` is used.
  See [`CONFIGURATION.md`](CONFIGURATION.md) and
  [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md#port-already-in-use--cant-bind)
  for the exact fallback rules.
- `--host`, when passed explicitly, is persisted to `config.json` for future
  starts (`bind_host` key).
- `--verbose` also flows through to background starts (passed to the
  spawned `--server-mode` process).

### `stop`

```
ariami_cli stop
```

Sends `SIGTERM` (Unix) / `taskkill /F` (Windows) to the PID recorded in
`ariami.pid`, waits ~500ms, then removes the PID file
(`lib/services/daemon_service.dart`). Prints
`Ariami CLI server is not running.` if there is no recorded/matching PID.
Does not accept any flags — passing one prints a usage error and exits `2`.

### `status`

```
ariami_cli status
```

Prints a live health-check snapshot: CLI version, whether the process is
running (with PID/uptime when known), whether the dashboard actually
answers over HTTP on `127.0.0.1:<port>/api/server-info` (a 2-second-timeout
probe — see `lib/services/server_status_service.dart`), the server's own
reported version if it differs from the CLI's, LAN/Tailscale URLs, setup
completion, music folder path (and whether it currently exists), account
count, the active data directory, and the names of the database/cache
files/directories inside it. Never fails loudly — on an unexpected error it
falls back to printing just the CLI version and `Server:    status
unavailable`.

### `help [topic]`

```
ariami_cli help
ariami_cli help tailscale
ariami_cli help music-folder
ariami_cli help scan
ariami_cli help owner
ariami_cli help connect
```

Prints plain-language guidance (`lib/services/cli_guidance.dart`). With no
topic, prints the overview plus the list of topics above. An unknown topic
prints `Error: unknown help topic "<topic>".` and exits `2`. More than one
topic argument prints `Error: help accepts at most one topic.` and exits `2`.

### `configure --music-folder <path>`

```
ariami_cli configure --music-folder /home/user/Music
```

Sets the music folder path without going through the web wizard. Validates
the path first (must exist, be a directory, and be readable — see
`ariami_core/lib/services/setup/music_folder_path_helper.dart`) and prints
one of:

- `Music folder saved: <path>` on success.
- `Error: --music-folder requires a path.` if the flag was omitted or empty.
- `Error: <validation message>` otherwise, with an extra hint line for a
  missing path (`Check that the path exists on this machine.`) or a
  permission problem (`Ensure the server user can read this directory.`).

Only the `--music-folder` option exists on this command.

### `music-folder set <path>`

```
ariami_cli music-folder set /home/user/Music
```

Equivalent alternate spelling of `configure --music-folder`, using the same
validation and the same `ConfigureCommand` underneath
(`bin/ariami_cli.dart`). `music-folder <anything else>`, or a missing/blank
path, prints a `Usage: ariami_cli music-folder set <path>` error and exits
`2`.

### `autostart [enable|disable|status]`

```
ariami_cli autostart enable
ariami_cli autostart disable
ariami_cli autostart status
```

Defaults to `status` when no action is given. `on`/`off` are accepted as
synonyms for `enable`/`disable`. Uses the platform's native mechanism, no
sudo required (`lib/services/autostart_service.dart`):

| Platform | Mechanism |
| --- | --- |
| Linux | An `@reboot` crontab entry for the current user, tagged with a marker comment so it can be found and removed cleanly. Output is appended to `autostart.log` in the Ariami data directory. |
| macOS | A LaunchAgent plist at `~/Library/LaunchAgents/com.ariami.cli.plist` with `RunAtLoad`, `StandardOutPath`/`StandardErrorPath` pointed at `autostart.log`. |
| Windows | An `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` registry value named `AriamiCLI`. |

Any other platform (or if the underlying command fails) prints
`Start-on-boot is not supported on this platform.` or
`ERROR: Could not enable/disable start-on-boot.` and exits `1`. An unknown
action prints `Error: unknown autostart action "<action>".` and exits `1`.

### `reset [--setup | --factory] [--yes|-y]`

```
ariami_cli reset                 # interactive menu
ariami_cli reset --setup         # setup/config only, keeps library + accounts
ariami_cli reset --factory -y    # factory reset, no prompts
```

With no scope flag, shows an interactive menu (`1` setup-only, `2` factory,
`3` cancel) and, unless `-y`/`--yes` was passed, requires typing `RESET` to
confirm. Passing both `--setup` and `--factory` prints
`Error: choose only one of --setup or --factory.` and exits `2`. If the
server is currently running, `reset` stops it first (and aborts with exit
`1` if the stop fails). See
[`CONFIGURATION.md`](CONFIGURATION.md#reset-scopes) for exactly which files
each scope removes, and the safety guarantees (the configured music folder
path is never touched, even if it happens to nest inside the data directory).

## Exit codes

Verified from `bin/ariami_cli.dart` and the command implementations:

| Code | Meaning |
| --- | --- |
| `0` | Success, or a graceful shutdown (signal received, cleanup completed). Also used when stdout gets a broken pipe (e.g. `ariami_cli status \| head`) — treated as a normal end of pipeline, not a crash. |
| `1` | A fatal runtime error: an uncaught exception during command execution, a failed background daemon start, a failed `reset` when the running server couldn't be stopped, or a failed `autostart enable`/`disable`. |
| `2` | A usage/argument error: bad or missing arguments, an unknown command, an unknown `help` topic, too many `help` arguments, a bad `music-folder` invocation, or `reset --setup --factory` together. |

## Notes on `--server-mode`

`--server-mode` is intentionally undocumented in `--help` (`hide: true` in
the parser) because it isn't meant for interactive use. It's what `start`'s
background daemon actually runs, and what a systemd unit or Docker container
should invoke directly so the process stays in the foreground under that
supervisor's control instead of double-daemonizing. In this mode, port
fallback is disabled (an explicit `--port` is required to already be free),
and the process retries binding with exponential backoff (100ms, 200ms,
400ms, ... up to 10 attempts) to ride out the brief window where the
previous foreground setup process is still releasing the port during the
handoff to background. See `docker/DOCKER.md` and the systemd unit example
in `../HEADLESS.md` for real usage.
