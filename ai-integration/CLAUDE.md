# FDA Tunnel — Full Disk Access for Interpreter Binaries

## What this is

macOS TCC (Transparency, Consent, and Control) blocks launchd and cron processes from reading protected user data — Safari history, cookies, Mail, Messages, and more. Terminal.app has Full Disk Access, but launchd jobs don't inherit it.

**FDA tunnel** = a copy of an interpreter binary (Python, Node, Ruby, etc.) at a stable path, with Full Disk Access granted in System Settings. It acts as a tunnel — any script you run through it gets access to TCC-protected paths, no per-script authorization needed.

## When to use

When a script needs to read any of these from launchd, cron, or any non-interactive context:
- `~/Library/Safari/History.db`
- `~/Library/Safari/Bookmarks.plist`
- `~/Library/Cookies/Cookies.binarycookies`
- `~/Library/Mail/`
- `~/Library/Messages/chat.db`
- `~/Library/Calendars/`
- `~/Library/Suggestions/snippets.db`

## How to use

Instead of:
```
python3 your_script.py
node your_script.js
```

Use:
```
~/.local/bin/fda-python3 your_script.py
~/.local/bin/fda-node your_script.js
```

In launchd plists, use the FDA binary path in ProgramArguments:
```xml
<key>ProgramArguments</key>
<array>
    <string>/Users/USERNAME/.local/bin/fda-python3</string>
    <string>/path/to/script.py</string>
</array>
```

## Rules

- FDA is **path-based**. Never move or rename the binary — it loses FDA.
- The `.app` wrapper approach (osacompile) does NOT work — child processes don't inherit FDA.
- Symlinks don't work — macOS resolves to the target and checks that path's FDA status.
- `/usr/bin/python3` is an Apple shim, not a real binary — don't use it for FDA.
- If Homebrew upgrades the source interpreter, the FDA copy at `~/.local/bin/` still works (it's a separate file). But it may be outdated — re-run `setup.sh` to update.

## Setup

```bash
# Clone and run
git clone https://github.com/civillizard/MacOS-Full-Disk-Access-Tunnel.git
cd MacOS-Full-Disk-Access-Tunnel
./setup.sh python3    # or: node, ruby, /path/to/binary
./verify.sh           # confirm FDA works
```

The setup script copies the real binary to `~/.local/bin/fda-<name>`. One manual step is needed: drag the binary onto the Full Disk Access list in System Settings (macOS enforces GUI interaction for this).
