# `rds-ip.sh`

Lists, adds or removes MySQL (port 3306) inbound rules on the security group for the
RDS instance. Use it to keep the allowlist current, for example when a home IP
changes.

## Usage

```sh
rds-ip.sh list
rds-ip.sh add <ip|cidr|me> [description] [--dry-run]
rds-ip.sh remove <ip|cidr|me> [--dry-run]
```

| Argument      | Meaning |
| ------------- | ------- |
| `list`        | Show the CIDRs and descriptions allowed on 3306. |
| `add`         | Allow an IP or CIDR. A bare IP becomes a `/32`. |
| `remove`      | Remove the rule for an IP or CIDR. It must match the rule exactly, so `remove 0.0.0.0/0` removes the open rule. |
| `me`          | This machine's current public IP, from `checkip.amazonaws.com`. |
| `description` | Label shown in `list` and the AWS console. AWS allows letters, digits, spaces and `._:/()#,@+=&;{}!$*-`. |
| `--dry-run`   | Checks your IAM permissions and changes nothing. AWS reports a successful dry run as an error: "Request would have succeeded, but DryRun flag is set". |

Only IPv4 is supported.

## Examples

```sh
rds-ip.sh add 1.1.1.1 "office"
rds-ip.sh add me "home"

# Home IP changed
rds-ip.sh list
rds-ip.sh remove 1.1.1.1
rds-ip.sh add me "home"
```

Add every IP you need (office, home, server outbound ranges) and check them with
`list` before you remove `0.0.0.0/0`. Anything not on the list loses database access as
soon as the open rule is gone.

## Render outbound IPs

Render doesn't publish its ranges in its docs. Open any service in the dashboard, click
**Connect**, then the **Outbound** tab. All services in a region share the same ranges,
so you only need to look once per region. The ranges are also shared with other Render
customers, so keep TLS and strong passwords in place.
Docs: <https://render.com/docs/outbound-ip-addresses>

## Configuration

| Variable     | Default                | Meaning |
| ------------ | ---------------------- | ------- |
| `RDS_SG`     | `sg-028947da35379541b` | Security group to change. |
| `RDS_REGION` | `us-east-1`            | AWS region. |

## Dependencies

```sh
brew install awscli
aws configure
```

The AWS user needs this IAM policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "ec2:DescribeSecurityGroups", "Resource": "*" },
    { "Effect": "Allow",
      "Action": ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"],
      "Resource": "arn:aws:ec2:us-east-1:{securitygroup}" }
  ]
}
```

`curl` is used for `me`. macOS ships it.
