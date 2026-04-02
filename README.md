# macOS Full Disk Access Tunnel

Run scheduled scripts that read Safari history, cookies, Mail, Messages, and other protected data — without macOS blocking access.

## The Problem

macOS TCC (Transparency, Consent, and Control) protects sensitive user data. When you open Terminal and run a Python script that reads `~/Library/Safari/History.db`, it works — because Terminal.app has Full Disk Access (FDA).

But the same script fails silently when run from:
- **launchd** (scheduled tasks / LaunchAgents)
- **cron**
- **SSH sessions**
- **CI runners**
- **Any non-interactive context**

The error is usually `unable to open database file` or just empty results. No clear message that TCC blocked the access.

## The Fix

Grant Full Disk Access to the interpreter binary itself — not to Terminal, not to an .app wrapper, not to the script file. The actual binary.

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

Works with any interpreter — Python, Node.js, Ruby, Perl, or any Mach-O binary.

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

## AI Tool Integration

If you use AI coding tools (Claude Code, Cursor, GitHub Copilot), you can give them context about FDA tunnels so they write correct automation scripts.

Drop-in instructions for each tool are in the [`ai-integration/`](ai-integration/) folder:

| Tool | File | Where to put it |
|------|------|-----------------|
| **Claude Code** | [`CLAUDE.md`](ai-integration/CLAUDE.md) | Copy content into your project's `CLAUDE.md` or `~/.claude/CLAUDE.md` |
| **Cursor** | [`cursor-rules.md`](ai-integration/cursor-rules.md) | Copy content into `.cursorrules` or `.cursor/rules/fda.md` |
| **GitHub Copilot** | [`copilot-instructions.md`](ai-integration/copilot-instructions.md) | Copy content into `.github/copilot-instructions.md` |
| **Other tools** | Use any of the above | The content is the same rules in different formats |

The key rule for any AI tool: **when writing a script that reads TCC-protected data and will run from launchd/cron, use `~/.local/bin/fda-<interpreter>` instead of the regular binary path.**

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
A: It's the same level of access Terminal.app has. The binary can only read files your user account owns — it doesn't bypass file permissions or give root access. You're choosing to let a specific binary read your own data.

**Q: Does this survive macOS updates?**
A: The binary copy survives. But major macOS updates sometimes reset TCC grants. If it stops working after an OS update, re-add the binary to the FDA list in System Settings.

**Q: Can I use this for multiple interpreters?**
A: Yes. Run `setup.sh` once per interpreter. Each gets its own FDA binary and its own TCC entry.

## Tested On

- macOS Sequoia (15.x) — Apple Silicon
- macOS Tahoe (26.x) — Apple Silicon

Should work on macOS Ventura (13.x) and later. TCC has existed since macOS Mojave (10.14) but the FDA category was formalized in Catalina (10.15).

## License

MIT
