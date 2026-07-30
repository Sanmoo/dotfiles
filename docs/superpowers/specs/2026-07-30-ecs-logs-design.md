# ECS Logs Script Design

## Goal

Add `general/bin/ecs-logs`, an executable Bash script that follows CloudWatch logs for an ECS service using only AWS CLI commands.

## Interface

```text
ecs-logs <cluster> <service> [aws logs tail arguments...]
```

Cluster and service are required. Remaining arguments are passed unchanged to `aws logs tail`, enabling options such as `--since` and `--format`.

AWS profile and region come from normal AWS CLI configuration or environment variables such as `AWS_PROFILE` and `AWS_REGION`. Extra arguments are not passed to discovery calls because log-tail-specific options are invalid for ECS commands.

## Flow

1. Validate argument count and AWS CLI availability.
2. Call `aws ecs describe-services` to resolve the service task definition ARN.
3. Call `aws ecs describe-task-definition` to read every container's `awslogs-group` value.
4. Remove empty values and duplicates.
5. If no log group exists, fail with a clear message.
6. If multiple distinct log groups exist, fail and list them.
7. Replace the script process with:

   ```bash
   aws logs tail "$log_group" --follow "${extra_args[@]}"
   ```

AWS CLI handles authentication, authorization, pagination, output streaming, interruption, and service errors.

## Error Handling

The script uses strict Bash mode. It reports:

- missing required arguments;
- missing `aws` executable;
- service not found or service without a task definition;
- task definition without an `awslogs` log group;
- multiple distinct log groups, including their names.

AWS CLI failures retain their original stderr and non-zero status.

## Testing

Use a temporary mock `aws` executable placed first in `PATH`. Cover:

- successful discovery and tail invocation;
- passthrough of extra `aws logs tail` arguments;
- missing service/task definition;
- no configured log group;
- multiple distinct log groups;
- missing required arguments.

Tests must not contact AWS.
