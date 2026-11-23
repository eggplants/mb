// The bw CLI with the client certificate of preload.cjs, for the Bitwarden MCP server
// (npm:@bitwarden/mcp-server), which setup:claude registers with BW_CLI_PATH pointing here. The
// server starts bw with a filtered environment that drops NODE_OPTIONS, so the bw() shell
// function's --require does not reach it; it runs this .cjs file with its own node instead
// (`node bw.cjs <args>`), and this file loads the preload and then the CLI's entry point.
"use strict";

const fs = require("node:fs");
const path = require("node:path");

// the bw CLI's JS entry point, from the first bw on PATH: an npm symlink to it, or a shim
// (mise's node_modules/.bin/bw, npm's bw.cmd on Windows) next to the @bitwarden/cli package
function entry() {
  const exts = process.platform === "win32" ? [".exe", ".cmd", ".ps1", ""] : [""];
  for (const dir of (process.env.PATH || "").split(path.delimiter)) {
    for (const ext of exts) {
      const bw = path.join(dir || ".", `bw${ext}`);
      let real;
      try {
        real = fs.realpathSync(bw);
        if (!fs.statSync(real).isFile()) continue;
      } catch {
        continue;
      }
      if (/\.[cm]?js$/.test(real)) return real;
      try {
        const pkg = require.resolve("@bitwarden/cli/package.json", { paths: [path.dirname(bw)] });
        const { bin } = JSON.parse(fs.readFileSync(pkg, "utf8"));
        return path.join(path.dirname(pkg), typeof bin === "string" ? bin : bin.bw);
      } catch {
        // a bw that is not the npm @bitwarden/cli (e.g. a mise shim): try the next one
      }
    }
  }
  return undefined;
}

const cli = entry();
if (!cli) {
  console.error("bw.cjs: the npm @bitwarden/cli is not on PATH");
  process.exit(127);
}
// a locked bw would otherwise prompt for the master password on the server's stdin pipe and hang
// the tool call (the server has no timeout); the unlock tool passes it with --passwordenv
process.env.BW_NOINTERACTION = "true";
require("./preload.cjs");
require(cli);
