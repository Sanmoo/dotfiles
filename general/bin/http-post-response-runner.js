#!/usr/bin/env node
/*
 * Deliberately small Bruno-compatible response surface for http oc.
 * This is not a security sandbox: only run trusted collection scripts.
 */
"use strict";

const fs = require("fs");
const vm = require("vm");

let input;
try {
  input = JSON.parse(fs.readFileSync(0, "utf8"));
} catch (error) {
  console.error(`invalid post-response runtime input: ${error.message}`);
  process.exit(1);
}

const responseHeaders = Object.assign({}, input.headers || {});
const response = {
  body: input.body,
  status: input.status,
  headers: responseHeaders,
  getBody() { return this.body; },
  getStatus() { return this.status; },
  getHeaders() { return this.headers; },
  getHeader(name) {
    const wanted = String(name).toLowerCase();
    const key = Object.keys(this.headers).find((candidate) => candidate.toLowerCase() === wanted);
    return key === undefined ? undefined : this.headers[key];
  },
};

const context = vm.createContext({
  res: response,
  console: {
    log: (...values) => console.error(...values),
    error: (...values) => console.error(...values),
  },
});

try {
  vm.runInContext(input.code, context, { timeout: 10000, displayErrors: true });
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
