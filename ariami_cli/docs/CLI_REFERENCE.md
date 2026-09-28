# CLI Reference

Every command, flag, and exit code below comes from the argument parser in
`bin/ariami_cli.dart` and the command classes in `lib/commands/`. If a flag
is not listed here, the CLI does not accept it.

## Global usage

```
ariami_cli <command> [options]
```

Global flags (parsed by the top-level `ArgParser` in `bin/ariami_cli.dart`):

| Flag | Abbr | Meaning |
| --- | --- | --- |
| `--help` | `-h` | Show the built-in help/usage text and exit. |
| `--version` | `-v` | Print `Ariami CLI version <version>` (from `kAriamiVersion`) and exit. |
| `--port <port>` | `-p` | Server port. Default `8080`, or the `ARIAMI_PORT` value when that is set. |
| `--host <address>` | | HTTP bind address. Default `0.0.0.0`. |
| `--no-browser` | | During setup, print URLs and never auto-open a browser. |
| `--verbose` | | Show stack traces and extra debug output for startup failures. |
| `--server-mode` | | **Hidden/internal.** Runs the HTTP server in the foreground for a supervisor (systemd, Docker). Not meant to be run by hand outside a service unit. |
| `--setup` | | Used with `reset`: setup/config only. |
| `--factory` | | Used with `reset`: factory reset all data. |
| `--yes` | `-y` | Used with `reset`: skip the confirmation prompt. |

An explicit `--port`, or an `ARIAMI_PORT` value, counts as the port you asked
for and disables the `8080` to `8099` fallback scan. First run and
`--server-mode` use it directly. A normal `start` after setup keeps using the
port saved in `config.json` instead (see [`start`](#start)).

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
  `Start Ariami automatically on boot (after restart, etc.)? [y/N]:`. A
  non-interactive session (no TTY, or stdin at EOF) skips the prompt and
  tells you to run `ariami_cli autostart enable` later
  (`lib/commands/start_command.dart`). It then prints the setup URLs
  (`This machine`, `Same network`, `Tailscale` when detected) and opens a
  browser unless `--no-browser` was passed. When the web wizard finishes,
  the process moves itself into a background daemon automatically and the
  foreground process exits.
- Subsequent runs (setup already complete): starts the server directly **in
  the background** and returns control of the terminal immediately, printing
  a startup summary (PID, dashboard/LAN/Tailscale URLs, data dir, music
  folder, auth state).
- If the server is already running, prints
  `Ariami CLI server is already running.` and returns without error.
- `--port`/`-p` (or `ARIAMI_PORT`) matters only before a port has been saved
  during a first run. Once setup has saved a `server_port`, later `start`
  runs reuse that saved value and ignore `--port`. To move an existing
  install, stop it, edit `server_port` in `config.json`, then start again.
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
Passing a flag prints a usage error and exits `2`.

### `status`

```
ariami_cli status
```

Prints a live health-check snapshot: CLI version, whether the process is
running (with PID/uptime when known), whether the dashboard actually answers
over HTTP on `127.0.0.1:<port>/api/server-info` (a 2-second-timeout probe,
see `lib/services/server_status_service.dart`), the server's own reported
version if it differs from the CLI's, LAN/Tailscale URLs, setup completion,
music folder path (and whether it currently exists), account count, the
active data directory, and the names of the database/cache files/directories
inside it. If the snapshot cannot be collected, it prints just the CLI
version and `Server:    status unavailable`.

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
the path first (it must exist, be a directory, and be readable; see
`ariami_core/lib/services/setup/music_folder_path_helper.dart`) and prints:

- `Music folder saved: <path>` on success.
- `Error: --music-folder requires a path.` when the value is empty. This is
  a validation message, so the command still exits `0`.
- `Error: <validation message>` otherwise, plus a hint line for a missing
  path (`Check that the path exists on this machine.`) or a permission
  problem (`Ensure the server user can read this directory.`). These also
  exit `0`.

Omitting `--music-folder` entirely is a usage error: it prints
`Error: configure requires at least one option.` plus the usage line and
exits `2`. Only the `--music-folder` option exists on this command.

### `music-folder set <path>`

```
ariami_cli music-folder set /home/user/Music
```

Alternative spelling of `configure --music-folder`, using the same
validation and the same `ConfigureCommand` underneath
(`bin/ariami_cli.dart`). `music-folder <anything else>`, or a missing/blank
path, is a usage error: `Error: unknown music-folder subcommand.` or
`Error: music-folder set requires a path.`, plus
`Usage: ariami_cli music-folder set <path>`, exit `2`. A path that fails
validation prints the same messages as `configure` and exits `0`.

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

An unsupported platform prints
`Start-on-boot is not supported on this platform.` and exits `0` without
changing anything. A failed enable/disable prints
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
each scope removes, and the safety guarantee that the configured music
folder path is never touched, even if it happens to nest inside the data
directory.

## Exit codes

Verified from `bin/ariami_cli.dart` and the command implementations:

| Code | Meaning |
| --- | --- |
| `0` | Success, or a graceful shutdown (signal received, cleanup completed). Also used when stdout gets a broken pipe (e.g. `ariami_cli status \| head`), and when `configure` or `music-folder set` rejects a path or an empty value with an error message. |
| `1` | A fatal runtime error: an uncaught exception during command execution, a failed background daemon start, a failed move to the background after setup, a failed `reset` when the running server couldn't be stopped, a failed `autostart enable`/`disable`, or an unknown `autostart` action. |
| `2` | A usage/argument error: bad or missing arguments, an invalid `--port` or `ARIAMI_PORT` value, an unknown command, an unknown `help` topic, too many `help` arguments, a flag passed to `stop`/`status`/`autostart`, a bad `music-folder` invocation, or `reset --setup --factory` together. |

## Notes on `--server-mode`

`--server-mode` is intentionally undocumented in `--help` (`hide: true` in
the parser) because it isn't meant for interactive use. It's what `start`'s
background daemon actually runs, and what a systemd unit or Docker container
should invoke directly, so the process stays in the foreground under that
supervisor's control instead of double-daemonizing.

The port comes from `--port`, else `ARIAMI_PORT`, else `8080`; the saved
`server_port` from `config.json` is not consulted here (a normal `start`
passes the saved port through explicitly). Port fallback is disabled, so
that exact port must be free, and the process retries the bind with
exponential backoff (100ms, 200ms, 400ms, ... up to 10 attempts) to ride out
the brief window where the previous foreground setup process is still
releasing the port during the handoff to background. An explicit `--host` is
persisted to `config.json`, and the process writes its own `ariami.pid`. See
`docker/DOCKER.md` and the systemd unit example in `../HEADLESS.md` for real
usage.
