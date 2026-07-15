# Optional OpenCollection Query Parameters

## Goal

Allow one invocation of `http oc` to omit selected or all OpenCollection query parameters when their required values were not explicitly supplied. Preserve existing behavior when the feature is not enabled.

## Command-line interface

The `oc` command gains one repeatable option with a descriptive name and a compact alias:

```text
--disable-query-when-not-provided[=QUERY[,QUERY...]]
--dqwnp[=QUERY[,QUERY...]]
```

Usage:

```bash
# Treat every query parameter as optional for this invocation
http oc get-users --dqwnp

# Treat only page and limit as optional
http oc get-users --dqwnp=page,limit

# Repeated options are also accepted
http oc get-users --dqwnp=page --dqwnp=limit
```

Names refer to the `name` field of entries in `request.params` whose type is `query`.

The equals sign is required when supplying names. This avoids ambiguity between an optional flag value and the positional request name. A bare `--dqwnp` always means all query parameters.

## Meaning of “provided”

For query parameters covered by this option, only variables explicitly supplied with `-v/--var` count as initially provided. Values inherited from the collection, request, or environment do not enable an optional query parameter.

An explicit empty value, such as `-v pageNumber=`, disables every covered query parameter that requires that variable.

A covered query parameter with multiple template variables is enabled only if every required variable is explicitly supplied with a non-empty value. If any required variable is absent or empty, the entire query parameter is omitted.

A covered query whose name and value contain no template variables remains enabled because it has no value that can be provided or left empty. YAML `disabled: true` or a future unconditional-removal feature would be required to omit such a literal query.

If a request contains multiple query entries with the same name, a named option applies to all of them.

Query parameters not covered by the option retain their current behavior.

## Interactive flow

After collection, request, and environment selection, and before prompting for missing variable values, `http oc` checks whether the request contains query parameters.

If the request has queries and `--dqwnp` was not supplied, it asks:

```text
Allow disabling query parameters with an empty value? [y/N]
```

`Enter` or `n` preserves the current behavior. Answering `y` is equivalent to a bare `--dqwnp` and applies to all query parameters.

For a covered query parameter, each absent variable is prompted as:

```text
value for pageNumber (leave empty to disable):
```

An empty answer disables the entire query parameter. With multiple variables, each variable is requested separately; any empty answer disables the query.

The activation question is not shown when:

- the request has no query parameters;
- `--dqwnp` was already supplied; or
- the invocation is non-interactive.

## Non-interactive flow

`--no-interactive` never produces prompts.

With a bare `--dqwnp`, every query parameter lacking explicit, non-empty values for all its variables is omitted. With named options, the rule applies only to those query parameters. This omission is silent because it was explicitly requested by the option.

## Validation and errors

After loading the request, explicitly named parameters are validated before variable prompting.

An unknown name produces an error and lists available query parameters:

```text
error: query parameter not found: pages; available: page, limit
```

A name that exists only as a path parameter produces:

```text
error: parameter is not a query parameter: customerId
```

Empty names in comma-separated lists are ignored consistently with the existing comma-separated `-v` parser.

A variable may be used by both an optional query and another required field such as the URL, path, header, body, or mandatory query. Omitting the optional query does not remove the variable requirement from those other fields. Existing missing-variable validation must still report it.

## Internal design

### Option normalization

Normalize parsed values into one of three states:

1. feature not requested;
2. all query parameters covered;
3. a set of explicitly named query parameters.

Repeated options and comma-separated names are merged into the same set. A bare occurrence takes precedence and selects all queries.

### Query analysis

Analyze query parameters before the general missing-variable prompt. For each covered query:

1. collect template variables from its name and value;
2. check those variables against the explicit CLI variable map;
3. in interactive mode, prompt for absent variables with the optional-query message;
4. mark the query disabled if any required value is empty;
5. otherwise merge prompted values into the resolved variable map.

Variables required outside disabled queries are then processed by the existing missing-variable flow. Query analysis must retain enough usage information to distinguish variables exclusive to an omitted query from variables still required elsewhere.

### Request construction

Pass the set of query names disabled for this invocation to request construction. `build_basic_oc_args` omits those entries in addition to entries already marked `disabled: true` in YAML. Headers, path parameters, body handling, authentication, and CLI-added `-q` values remain unchanged.

### Equivalent command

The displayed equivalent command records the effective choice:

- global interactive opt-in emits `--dqwnp`;
- a named selection emits a deterministic `--dqwnp=page,limit` list;
- empty prompted values are not emitted as `-v` because `--dqwnp` reproduces their omission.

## Compatibility

Invocations that do not use the option and decline the interactive prompt retain current semantics. YAML-level `disabled: true` remains authoritative. CLI `-q` values continue to append query parameters and are not candidates for this feature.

## Testing

Extend `tests/http-oc-test.sh` to cover:

1. bare `--dqwnp` omitting all queries without explicit values;
2. named selection affecting only selected queries;
3. repeated options and comma-separated names;
4. explicit empty CLI values disabling without a prompt;
5. multi-variable queries being omitted when any value is empty;
6. literal queries without template variables remaining enabled;
7. duplicate query names all being covered by a named option;
8. unselected queries retaining current required-variable behavior;
9. inherited collection, request, and environment defaults not enabling covered queries;
10. clear errors for unknown names and path parameters;
11. interactive acceptance and refusal of global activation;
12. empty interactive values omitting a query;
13. equivalent commands containing global or named option forms;
14. shared variables remaining required outside omitted queries;
15. requests without queries not showing the activation question;
16. unchanged behavior when the option is not enabled.
