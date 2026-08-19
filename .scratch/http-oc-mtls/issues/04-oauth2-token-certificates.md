# 04 — Client certificates on OAuth2 token requests

**What to build:** the OAuth2 token requests (`client_credentials` and `authorization_code`) receive the client certificate matched by their own `tokenUrl` host, using the merged collection/environment certificate lists. A token endpoint whose host matches an entry gets `--cert`/`--key`/`--pass` on the token call; a host matching nothing keeps today's behaviour. The token cache is unchanged: cached tokens skip the curl call entirely, and `--auth-no-cache` still forces a refetch.

**Blocked by:** 02 — Client certificates per environment with precedence.

**Status:** ready-for-agent

- [ ] A `client_credentials` token call to a host matching a certificate entry receives the certificate flags
- [ ] An `authorization_code` token call to a host matching a certificate entry receives the certificate flags
- [ ] A token host matching no entry produces no certificate flags (behaviour unchanged)
- [ ] Environment-level certificates apply to token matching the same way they apply to the main request
- [ ] A cached token skips the token curl call entirely, with or without certificates configured
- [ ] `--auth-no-cache` refetches and applies the matching certificate on the refetch
- [ ] Token-call certificate flags are covered at the process boundary (stub curl capturing the token invocation)
