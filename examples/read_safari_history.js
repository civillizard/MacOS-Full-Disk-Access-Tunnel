#!/usr/bin/env node
/**
 * Read Safari browsing history via FDA tunnel.
 *
 * Usage:
 *   ~/.local/bin/fda-node read_safari_history.js
 *
 * Requires: npm install better-sqlite3
 * (or use the built-in sqlite module in Node 22+)
 *
 * Will fail with SQLITE_CANTOPEN if run with regular node from launchd/cron.
 */

const path = require("path");
const os = require("os");
const fs = require("fs");

const SAFARI_HISTORY = path.join(os.homedir(), "Library/Safari/History.db");
const CORE_DATA_EPOCH = 978307200;

// Check access before trying to open
if (!fs.existsSync(SAFARI_HISTORY)) {
  console.error("Safari History.db not found");
  process.exit(1);
}

try {
  fs.accessSync(SAFARI_HISTORY, fs.constants.R_OK);
} catch {
  console.error("Cannot read History.db — FDA not granted to this Node binary");
  console.error(`Binary: ${process.execPath}`);
  console.error();
  console.error(
    "Fix: grant Full Disk Access to this binary in System Settings,",
  );
  console.error("or run with an FDA-tunneled binary:");
  console.error(`  ~/.local/bin/fda-node ${__filename}`);
  process.exit(1);
}

// Try better-sqlite3 first, fall back to Node 22+ built-in
let Database;
try {
  Database = require("better-sqlite3");
} catch {
  try {
    // Node 22.5+ has built-in SQLite (experimental)
    const { DatabaseSync } = require("node:sqlite");
    // Wrap to match better-sqlite3 API
    Database = class {
      constructor(path, opts) {
        this.db = new DatabaseSync(path, opts);
      }
      prepare(sql) {
        const stmt = this.db.prepare(sql);
        return { all: (...args) => stmt.all(...args) };
      }
      close() {
        this.db.close();
      }
    };
  } catch {
    console.error("No SQLite library available.");
    console.error("Install: npm install better-sqlite3");
    console.error("Or use Node 22.5+ (has built-in sqlite).");
    process.exit(1);
  }
}

const db = new Database(SAFARI_HISTORY, { readonly: true });

const rows = db
  .prepare(
    `
    SELECT
        hi.url,
        hv.title,
        datetime(hv.visit_time + 978307200, 'unixepoch', 'localtime') as visit_date
    FROM history_items hi
    JOIN history_visits hv ON hi.id = hv.history_item
    ORDER BY hv.visit_time DESC
    LIMIT 20
`,
  )
  .all();

db.close();

if (rows.length === 0) {
  console.log("No history entries found");
  process.exit(0);
}

for (const { url, title, visit_date } of rows) {
  const t = title || "(no title)";
  console.log(`  ${visit_date}  ${t.slice(0, 60)}`);
  console.log(`    ${url.slice(0, 100)}`);
  console.log();
}
