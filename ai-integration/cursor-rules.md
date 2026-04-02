# FDA Tunnel Rules (for .cursorrules or .cursor/rules/)

Paste the following into your `.cursorrules` file or create a file in `.cursor/rules/`:

---

## macOS FDA Tunnel

When a script needs to read TCC-protected data (Safari history, cookies, Mail, Messages) from launchd or cron:

- Use `~/.local/bin/fda-python3` instead of `python3`
- Use `~/.local/bin/fda-node` instead of `node`
- Use `~/.local/bin/fda-ruby` instead of `ruby`
- These are copies of the real binaries with Full Disk Access granted in System Settings — they act as tunnels, so any script run through them gets access without per-script authorization
- FDA is path-based — never move or rename these binaries
- Symlinks don't get FDA — must be an actual file copy
- The `.app` wrapper approach does NOT work (child processes don't inherit FDA)
- `/usr/bin/python3` is an Apple shim — don't use it for FDA

### TCC-protected paths (need FDA to read)
- `~/Library/Safari/History.db`
- `~/Library/Cookies/Cookies.binarycookies`
- `~/Library/Mail/`
- `~/Library/Messages/chat.db`
- `~/Library/Calendars/`

### In launchd plists
```xml
<key>ProgramArguments</key>
<array>
    <string>/Users/USERNAME/.local/bin/fda-python3</string>
    <string>/path/to/script.py</string>
</array>
```
