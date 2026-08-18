# Dotfiles

Personal configuration and command-line tooling managed with GNU Stow, including an HTTP client (`http`) used for ad-hoc API consumption against OpenCollection collections.

## Language

**Collection**:
A directory containing a manifest plus one or more request documents; identified by its manifest.
_Avoid_: collection folder, project, collection dir

**Manifest**:
The collection's top-level YAML file (`opencollection.yaml`, `opencollection.yml`, `collection.yaml`, or `collection.yml`) holding `info`, `variables`, `config.environments`, and request defaults.
_Avoid_: collection config, opencollection file

**Request document**:
A YAML file (not a manifest) describing one named HTTP request — recognized by `type: http` or a `request:` block with `method`/`url`.
_Avoid_: request file, endpoint doc

**Request**:
The runnable HTTP call resolved from a request document (method, URL, headers, params, body).
_Avoid_: call, endpoint (when meaning the resolved call rather than the document)

**Environment**:
A named variable set under `config.environments`, selectable with `-e`.
_Avoid_: env, variable set

**Comando equivalente**:
The `http oc ...` command printed in interactive mode that reproduces a run (the code names it `equivalent command`).
_Avoid_: equivalent command (in user-facing prose)

**Body override**:
`-d`/`-f` supplying the request body from the command line, replacing the manifest's `request.body`.
_Avoid_: inline body, CLI body (when meaning the override mechanism)
