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

const initialVariables = Object.assign({}, input.variables || {});
const runtimeVariables = Object.create(null);
const assignedVariables = new Set();
const processEnvironment = Object.assign({}, input.processEnv || {});
const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
const bru = {
  getVar(name) {
    const key = String(name);
    if (hasOwn(runtimeVariables, key)) return runtimeVariables[key];
    return hasOwn(initialVariables, key) ? initialVariables[key] : undefined;
  },
  setVar(name, value) {
    const key = String(name);
    runtimeVariables[key] = value;
    assignedVariables.add(key);
  },
  getProcessEnv(name) {
    const key = String(name);
    return hasOwn(processEnvironment, key) ? processEnvironment[key] : undefined;
  },
  setEnvVar() {
    throw new Error("bru.setEnvVar is unsupported; use bru.setVar for temporary runtime variables");
  },
  setCollectionVar() {
    throw new Error("bru.setCollectionVar is unsupported; use bru.setVar for temporary runtime variables");
  },
};

const context = vm.createContext({
  res: response,
  bru,
  console: {
    log: (...values) => console.error(...values),
    error: (...values) => console.error(...values),
  },
});

const scripts = Array.isArray(input.scripts) ? input.scripts : [input.code];
const deadline = Date.now() + 10000;
try {
  for (const code of scripts) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      throw new Error("post-response script sequence exceeded the 10-second execution limit");
    }
    vm.runInContext(code, context, { timeout: remaining, displayErrors: true });
  }
  const assigned = Array.from(assignedVariables, (name) => ({
    name,
    type: typeof runtimeVariables[name],
    value: runtimeVariables[name],
  }));
  const exportSources = Array.isArray(input.exportSources) ? input.exportSources : [];
  const exports = exportSources.map((source) => {
    const match = assigned.find((entry) => entry.name === source);
    return match || null;
  });
  process.stdout.write(JSON.stringify({ assigned, exports }));
} catch (error) {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
}
