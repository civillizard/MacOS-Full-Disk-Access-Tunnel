# FDA Tunnel Instructions (for GitHub Copilot)

Paste the following into your `.github/copilot-instructions.md`:

---

## macOS FDA Tunnel

On macOS, launchd and cron processes cannot read TCC-protected paths (Safari, Cookies, Mail, Messages). The workaround is an "FDA tunnel" — a copy of the interpreter binary with Full Disk Access granted. Any script run through the tunnel binary gets access, no per-script authorization needed.

FDA binaries live at `~/.local/bin/fda-<interpreter>`:
- `fda-python3` — for Python scripts
- `fda-node` — for Node.js scripts
- `fda-ruby` — for Ruby scripts

When writing automation scripts that read protected data:
1. Use the FDA binary path, not the system or Homebrew path
2. In launchd plists, set ProgramArguments to the FDA binary
3. Never move/rename FDA binaries (FDA is path-based)
4. Never use symlinks (macOS checks the resolved target's FDA status)
5. Never use .app wrappers (child processes don't inherit FDA)

Protected paths that need FDA:
- `~/Library/Safari/History.db`
- `~/Library/Cookies/Cookies.binarycookies`
- `~/Library/Mail/`
- `~/Library/Messages/chat.db`
- `~/Library/Calendars/`
- `~/Library/Suggestions/snippets.db`
