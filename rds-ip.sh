#!/usr/bin/env bash
# Manages MySQL (3306) inbound rules on the gccdb RDS security group.
#
# Usage:
#   rds-ip.sh list
#   rds-ip.sh add <ip|cidr|me> [description]
#   rds-ip.sh remove <ip|cidr|me>
#
# "me" is this machine's current public IP. A bare IP becomes a /32.
# Override the target with RDS_SG / RDS_REGION. Add --dry-run (last argument) to check IAM permissions without changing anything.
set -euo pipefail

SG="${RDS_SG:-sg-028947da35379541b}"
REGION="${RDS_REGION:-us-east-1}"
PORT=3306

usage() {
  sed -n '4,7p' "$0" | sed 's/^# *//'
  exit 1
}

to_cidr() {
  local ip="$1"
  [[ "$ip" == "me" ]] && ip="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
  [[ "$ip" == */* ]] || ip="$ip/32"
  local octet='(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])'
  if [[ ! "$ip" =~ ^($octet\.){3}$octet/([0-9]|[12][0-9]|3[0-2])$ ]]; then
    echo "Not an IPv4 address or CIDR: $1" >&2
    exit 1
  fi
  echo "$ip"
}

dry_run=()
if [[ "${*: -1}" == "--dry-run" ]]; then
  dry_run=(--dry-run)
  set -- "${@:1:$#-1}"
fi

case "${1:-}" in
  list)
    aws ec2 describe-security-groups --region "$REGION" --group-ids "$SG" \
      --query "SecurityGroups[0].IpPermissions[?FromPort==\`$PORT\`].IpRanges[]" --output table
    ;;
  add)
    [[ $# -ge 2 ]] || usage
    cidr="$(to_cidr "$2")"
    desc="${3:-}"
    # AWS allows only these characters in rule descriptions; quotes would also break the JSON below.
    if [[ ! "$desc" =~ ^[A-Za-z0-9\ ._:/\(\)#,@+=\&\;{}!\$*-]*$ ]]; then
      echo "Description has characters AWS rejects: $desc" >&2
      exit 1
    fi
    aws ec2 authorize-security-group-ingress ${dry_run[@]+"${dry_run[@]}"} --region "$REGION" --group-id "$SG" \
      --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":$PORT,\"ToPort\":$PORT,\"IpRanges\":[{\"CidrIp\":\"$cidr\",\"Description\":\"$desc\"}]}]" \
      >/dev/null
    echo "Added $cidr"
    ;;
  remove)
    [[ $# -eq 2 ]] || usage
    cidr="$(to_cidr "$2")"
    aws ec2 revoke-security-group-ingress ${dry_run[@]+"${dry_run[@]}"} --region "$REGION" --group-id "$SG" \
      --protocol tcp --port "$PORT" --cidr "$cidr" >/dev/null
    echo "Removed $cidr"
    ;;
  *)
    usage
    ;;
esac
