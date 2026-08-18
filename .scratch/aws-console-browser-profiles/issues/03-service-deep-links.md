# 03 — Service deep-links

**What to build:** A new optional positional service argument lands the federated console session directly on that service's console page: `aws-console ecs --profile rev-qual` opens the ECS console in the `aws-rev-qual` browser profile. A curated table maps the supported names (`ecs`, `ec2`, `lambda`, `s3`, `cloudwatch`, `logs`, `rds`, `dynamodb`, `ecr`, `iam`, `vpc`, `route53`, `sns`, `sqs`, `eks`) to their current, verified console URLs. Regional services append the region configured in the AWS profile; global services never carry a region. An unknown service name exits non-zero with the list of supported names. The deep-link works with and without `--profile`, and with `--stdout`.

**Blocked by:** 02 — Browser profile isolation

**Status:** ready-for-agent

- [ ] `aws-console ecs --profile rev-qual` sets the federation Destination to the current ECS console URL (with the profile's configured region) and opens it in the `aws-rev-qual` browser profile.
- [ ] All fifteen curated service names map to their current, verified console URLs (ECS uses its current console path).
- [ ] Regional services append `?region=<configured region>` when the AWS profile configures one; global services (`iam`, `s3`) never append a region.
- [ ] No region configured → no region parameter.
- [ ] Unknown service name exits non-zero and prints the supported names to stderr.
- [ ] Deep-link without `--profile` opens via the default browser (no isolation), still landing on the service page.
- [ ] Deep-link with `--stdout` prints only the service-aimed signin URL on stdout.
- [ ] Service URL building and region handling are covered by direct assertions on the pure helpers, including the global-vs-regional split.

## Comments
