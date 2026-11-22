// Loaded into the bw CLI with `node --require` by the bw() shell function (dotfiles/zshrc,
// conf.d/windows/pwsh/profile.ps1). bw.egpl.dev only answers clients that present a client
// certificate (mTLS at Cloudflare), and the npm @bitwarden/cli cannot present one: it fetches
// through node-fetch on Node's global https agent. This agent adds the certificate that
// setup:bitwarden extracted from ~/.bw.p12, on connections to that host only.
"use strict";

const fs = require("node:fs");
const https = require("node:https");
const os = require("node:os");
const path = require("node:path");

const host = "bw.egpl.dev";
const dir = path.join(os.homedir(), ".config", "bw-mtls");

let cert;
let key;
try {
  cert = fs.readFileSync(path.join(dir, "cert.pem"));
  key = fs.readFileSync(path.join(dir, "key.pem"));
} catch {
  // no certificate on this machine: leave the agent as it is
}

if (cert && key) {
  class ClientCertAgent extends https.Agent {
    createConnection(options, callback) {
      const name = options.servername || options.host;
      return super.createConnection(name === host ? { ...options, cert, key } : options, callback);
    }
  }
  https.globalAgent = new ClientCertAgent({ keepAlive: true });
}
