<p align="center">
  <img src="https://www.6ra3.com/track/fda/README" alt="macOS Full Disk Access Tunnel" width="800">
</p>

<p align="center"><sub>Logo images and outbound links are served through my analytics tracker to count page views and clicks. No personal data is collected.</sub></p>

# macOS Full Disk Access Tunnel

Grant Full Disk Access (FDA) to interpreter binaries so scheduled scripts can read TCC-protected data from launchd, cron, and SSH.

## What This Does

macOS TCC (Transparency, Consent, and Control) protects sensitive data — Safari history, cookies, Mail, Messages, contacts, calendars — and requires FDA to access it. FDA is granted to **binary paths**, not to scripts. This creates a gap for interpreter-based automation: when a Python, Node, or Ruby script needs TCC-protected data, there's no clean way to grant it access.

The workarounds people reach for don't hold up:

- **Grant FDA to the Homebrew interpreter** — works until `brew upgrade` changes the binary path and silently breaks the grant
- **Grant FDA to `/usr/bin/python3`** — works until a macOS update replaces it
- **Grant FDA to Terminal.app** — overly broad; gives *everything* in Terminal full access to protected data
- **Wrap in an `.app` bundle** — doesn't work for launchd or cron (no GUI context)

FDA Tunnel solves this: a stable, purpose-built binary copy at a fixed path that holds the FDA grant and delegates to your real interpreter. One binary, unlimited scripts, survives upgrades.

**This tool uses Apple's official FDA mechanism** — the same way Terminal.app gets access. It copies your interpreter binary to a stable path and walks you through granting FDA in System Settings. No SIP bypass, no TCC database editing, no security frameworks disabled. The user must manually approve access through the macOS GUI.

### Why not just grant FDA to the original interpreter?

You can. But Homebrew paths include version numbers (`/opt/homebrew/Cellar/python@3.12/3.12.12_2/...`). A `brew upgrade` changes that path and silently breaks the FDA grant. The copy at `~/.local/bin/fda-python3` is version-independent.

### Trade-offs

| | |
|---|---|
| **Pro** | Any script run through the FDA binary gets access — no per-script authorization needed |
| **Pro** | Stable path survives interpreter upgrades |
| **Pro** | Uses Apple's official FDA mechanism — same as Terminal.app |
| **Pro** | Original interpreter is untouched — no system binary modification |
| **Con** | The FDA binary has broad read access to user data — any script run through it inherits this |
| **Con** | macOS updates may reset TCC grants — you'll need to re-add the binary |
| **Con** | The binary copy is a point-in-time snapshot — security patches to the interpreter don't auto-apply (re-run setup to update) |

**This is a power-user tool.** It assumes you control which scripts run through the FDA binary. If you share your machine or run untrusted code, understand that anything executed via `fda-python3` can read your protected data.

## The Problem

When you run a Python script from Terminal that reads `~/Library/Safari/History.db`, it works — because Terminal.app has Full Disk Access.

But the same script fails silently when run from:
- **launchd** (scheduled tasks / LaunchAgents)
- **cron**
- **SSH sessions**
- **CI runners**
- **Any non-interactive context**

The error is usually `unable to open database file` or just empty results. No clear message that TCC blocked the access.

## The Fix

Grant Full Disk Access to a copy of the interpreter binary. Any script you run through it gets access. One binary, unlimited scripts.

This repo automates the setup:

```bash
git clone https://github.com/civillizard/MacOS-Full-Disk-Access-Tunnel.git
cd MacOS-Full-Disk-Access-Tunnel
./setup.sh python3
```

Then use the FDA binary instead of the regular one:

```bash
# Before (fails from launchd/cron):
python3 read_safari_history.py

# After (works everywhere):
~/.local/bin/fda-python3 read_safari_history.py
```

Works with any interpreter — Python, Node.js, Ruby, Perl, or any Mach-O binary. Grant FDA once, run any script through it.

## What Data is Protected

These paths need FDA to read from non-interactive contexts:

| Path | Contains |
|------|----------|
| `~/Library/Safari/History.db` | Browsing history |
| `~/Library/Safari/Bookmarks.plist` | Bookmarks |
| `~/Library/Cookies/Cookies.binarycookies` | Browser cookies |
| `~/Library/Mail/` | Email database |
| `~/Library/Messages/chat.db` | iMessage / SMS history |
| `~/Library/Calendars/` | Calendar data |
| `~/Library/Suggestions/snippets.db` | Siri suggestions |

FDA does **not** cover camera, microphone, screen recording, accessibility, or location — those are separate TCC categories with their own grant process.

## Setup

### Option A: Automated (recommended)

```bash
./setup.sh python3          # Python
./setup.sh node             # Node.js
./setup.sh ruby             # Ruby
./setup.sh /full/path/bin   # Any binary
```

The script:
1. Finds the real binary (resolves Homebrew symlinks)
2. Verifies it's a Mach-O executable (not a shim or wrapper)
3. Copies it to `~/.local/bin/fda-<name>`
4. Pins the Homebrew formula if applicable (prevents upgrades from breaking the source path)
5. Opens System Settings for the one manual step

**One manual step is always required.** macOS does not allow scripts to grant FDA — you must do it through the GUI. The setup script walks you through it.

### Option B: Manual (step by step)

If you prefer to understand each step or don't trust running scripts:

**Step 1 — Find the real binary**

Homebrew installs use symlinks. You need the actual file, not the symlink.

```bash
# Follow the symlink chain
which python3
# /opt/homebrew/bin/python3

ls -la /opt/homebrew/bin/python3
# -> ../Cellar/python@3.12/3.12.12_2/bin/python3.12

ls -la /opt/homebrew/Cellar/python@3.12/3.12.12_2/bin/python3.12
# -> ../Frameworks/Python.framework/Versions/3.12/bin/python3.12
```

The real binary for Homebrew Python is usually at:
```
/opt/homebrew/Cellar/python@3.12/VERSION/Frameworks/Python.framework/Versions/3.12/bin/python3.12
```

For Node.js:
```
/opt/homebrew/Cellar/node/VERSION/bin/node
```

Verify it's a real binary (not a script or shim):
```bash
file /opt/homebrew/Cellar/python@3.12/3.12.12_2/Frameworks/Python.framework/Versions/3.12/bin/python3.12
# Mach-O 64-bit executable arm64
```

**Step 2 — Copy to a stable path**

```bash
mkdir -p ~/.local/bin

cp /opt/homebrew/Cellar/python@3.12/3.12.12_2/Frameworks/Python.framework/Versions/3.12/bin/python3.12 \
   ~/.local/bin/fda-python3

chmod 755 ~/.local/bin/fda-python3
```

**Step 3 — Pin the Homebrew package**

This prevents `brew upgrade` from changing the Cellar path (which would make the version reference stale, though your copy still works):

```bash
brew pin python@3.12
```

**Step 4 — Grant Full Disk Access**

1. Open **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Click the **+** button
3. The file picker may grey out non-`.app` files. Workaround: open a Finder window to `~/.local/bin/`, then **drag** `fda-python3` onto the Full Disk Access list
4. Toggle it ON

```bash
# Open Finder to the right folder:
open ~/.local/bin/

# Open System Settings to the right pane:
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
```

**Step 5 — Verify**

```bash
./verify.sh ~/.local/bin/fda-python3
```

Or test manually:
```bash
~/.local/bin/fda-python3 -c "
import os
path = os.path.expanduser('~/Library/Safari/History.db')
print('FDA works' if os.access(path, os.R_OK) else 'FDA not granted')
"
```

## Using the FDA Binary

### In scripts

```bash
#!/usr/bin/env bash
~/.local/bin/fda-python3 /path/to/your_script.py
```

### In launchd plists

```xml
<key>ProgramArguments</key>
<array>
    <string>/Users/YOUR_USERNAME/.local/bin/fda-python3</string>
    <string>/Users/YOUR_USERNAME/scripts/your_script.py</string>
</array>
```

See [`examples/launchd_plist_example.plist`](examples/launchd_plist_example.plist) for a full example.

### In crontab

```
0 3 * * * /Users/YOUR_USERNAME/.local/bin/fda-python3 /path/to/script.py
```

## Approaches That Don't Work

These are common attempts that fail. Documenting them here so you don't spend time rediscovering them.

### .app wrapper (osacompile)

Wrapping the script in an `.app` bundle using `osacompile` and granting FDA to the `.app`. Fails because `do shell script` spawns a child process that doesn't inherit the app's FDA grant.

### Symlinks

Creating a symlink to the real binary and granting FDA to the symlink. macOS resolves the symlink and checks the target path's FDA status — the symlink itself isn't what gets checked.

### /usr/bin/python3

Apple's `/usr/bin/python3` is a shim that redirects to Xcode's Python. It doesn't behave like a normal binary for FDA purposes. Use the Homebrew binary instead.

### Granting FDA to the script file

macOS TCC checks the *process* binary, not the script being interpreted. Adding `your_script.py` to the FDA list does nothing — it's `python3` that needs FDA.

### Running from a Terminal.app subprocess

Terminal.app has FDA, and interactive sessions inherit it. But launchd jobs are not children of Terminal — they're started by the system directly.

## Examples

| File | What it does |
|------|-------------|
| [`read_safari_history.py`](examples/read_safari_history.py) | Read Safari browsing history (Python) |
| [`read_safari_history.js`](examples/read_safari_history.js) | Read Safari browsing history (Node.js) |
| [`export_cookies.py`](examples/export_cookies.py) | Export Safari cookies (Python) |
| [`launchd_plist_example.plist`](examples/launchd_plist_example.plist) | Launchd plist template using FDA binary |

Run any example:
```bash
~/.local/bin/fda-python3 examples/read_safari_history.py
~/.local/bin/fda-python3 examples/export_cookies.py --domain github.com
```

## How It Works

macOS TCC maintains a database at `/Library/Application Support/com.apple.TCC/TCC.db` that maps **binary paths** to permissions. When a process tries to read a protected path, the kernel checks if that process's binary has the right TCC entry.

Terminal.app has an FDA entry, so anything you run interactively inherits it. But launchd starts processes directly — no Terminal in the chain.

By copying the interpreter binary to a known path and granting FDA to that path:
1. The binary at `~/.local/bin/fda-python3` gets its own TCC entry
2. Any script run through it inherits FDA
3. The path never changes (unlike Homebrew Cellar paths that include version numbers)
4. The original interpreter is untouched — you're not modifying system binaries

This is the same pattern Apple uses for Terminal.app — the FDA grant is on the binary, and everything it runs gets access.

## FAQ

**Q: Does the FDA binary need to be updated when the interpreter gets a new version?**
A: No. The copy at `~/.local/bin/` is independent. It will keep working on the old version. Re-run `setup.sh` when you want to update it.

**Q: Can I grant FDA to the Homebrew binary directly instead of copying?**
A: You can, but the Cellar path includes the version number (e.g., `/opt/homebrew/Cellar/python@3.12/3.12.12_2/...`). A Homebrew upgrade changes that path and breaks the FDA grant. The copy at `~/.local/bin/` avoids this.

**Q: Does this work on Intel Macs?**
A: Yes. Homebrew paths differ (`/usr/local/` instead of `/opt/homebrew/`), but the setup script handles both.

**Q: Is this a security risk?**
A: It's the same level of access Terminal.app already has. The binary can only read files your user account owns — it doesn't bypass file permissions or give root access. You're choosing to let a specific binary read your own data. Any script run through it gets the same access — that's the tunnel.

**Q: Does this survive macOS updates?**
A: The binary copy survives. But major macOS updates sometimes reset TCC grants. If it stops working after an OS update, re-add the binary to the FDA list in System Settings.

**Q: Can I use this for multiple interpreters?**
A: Yes. Run `setup.sh` once per interpreter. Each gets its own FDA binary and its own TCC entry.

## Tested On

- macOS Sequoia (15.x) — Apple Silicon
- macOS Tahoe (26.x) — Apple Silicon

Should work on macOS Ventura (13.x) and later. TCC has existed since macOS Mojave (10.14) but the FDA category was formalized in Catalina (10.15).

## Related Reading

The FDA-for-interpreters problem has been discussed in fragments across the macOS community, but never consolidated into a single solution:

- [How to Give Full Disk Access to a Binary in macOS Mojave](https://www.6ra3.com/track/r/fda-n8henrie?dest=https://n8henrie.com/2018/11/how-to-give-full-disk-access-to-a-binary-in-macos-mojave/) — N8 Henrie (2018). First known write-up of dragging binaries into the FDA list.
- [launchctl, scheduling shell scripts on macOS, and Full Disk Access](https://www.6ra3.com/track/r/fda-kith?dest=https://kith.org/jed/2022/02/15/launchctl-scheduling-shell-scripts-on-macos-and-full-disk-access/) — Kith.org (2022). Covers the launchd + FDA interaction.
- [How to grant command line tools full disk access](https://www.6ra3.com/track/r/fda-apple-cli?dest=https://developer.apple.com/forums/thread/756510) — Apple Developer Forums. Thread on FDA for CLI tools.
- [Full disk access from a launchd daemon](https://www.6ra3.com/track/r/fda-apple-launchd?dest=https://developer.apple.com/forums/thread/661178) — Apple Developer Forums. Thread on launchd-specific FDA issues.
- [macOS 11.4 Breaks Full Disk Access for Helper Tools](https://www.6ra3.com/track/r/fda-tsai?dest=https://mjtsai.com/blog/2021/06/01/macos-11-4-breaks-full-disk-access-for-helper-tools/) — Michael Tsai (2021). Documents Apple breaking FDA inheritance for helper processes.

## AI Coding Tool Integration

The [`ai-integration/`](ai-integration/) folder has drop-in config files for Claude Code, Cursor, and GitHub Copilot. These tell the tool to use `fda-<interpreter>` when generating scripts that read TCC-protected data from launchd/cron.

## License

MIT

## Author & Contact

**Mamdoh AlOqiel** — Riyadh, Saudi Arabia

- **Email:** [mao@6ra3.com](mailto:mao@6ra3.com)
- **Issues & feedback:** [GitHub Issues](https://github.com/civillizard/MacOS-Full-Disk-Access-Tunnel/issues)
- **Contributions:** Pull requests welcome — open an issue first to discuss bigger changes

Open to collaboration on macOS automation, TCC/privacy tooling, and launchd/cron workflows.
