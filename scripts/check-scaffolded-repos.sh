#!/bin/sh
# Lists every scaffolded service that exists in only some of its three
# halves (ADR-0024): a repository in the idp-platform-apps organization, an
# ECR Public repository under idp-platform-apps/, and a Component entity in
# this repository carrying the platform.jordandesigns.io/repository
# annotation. The scaffolder run is not a transaction and teardown is three
# separate steps, so an abandoned half is found here rather than forgotten.
# Needs gh (read access to the organization) and AWS credentials that can
# describe ECR Public repositories. Exits 1 when anything is unmatched.
set -eu

org=idp-platform-apps
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gh repo list "$org" --limit 1000 --json name --jq '.[].name' | sort -u > "$tmp/github"

aws ecr-public describe-repositories --region us-east-1 --query 'repositories[].repositoryName' --output text \
  | tr '\t' '\n' | sed -n "s|^$org/||p" | sort -u > "$tmp/ecr"

for entity in backstage/catalog/resources/*/*.webservice.yaml; do
  [ -e "$entity" ] || continue
  sed -n "s|^    platform\.jordandesigns\.io/repository: *$org/||p" "$entity"
done | sort -u > "$tmp/catalog"

sort -u "$tmp/github" "$tmp/ecr" "$tmp/catalog" > "$tmp/all"

status=0
while read -r name; do
  [ -n "$name" ] || continue
  missing=
  grep -qx "$name" "$tmp/github" || missing="$missing github"
  grep -qx "$name" "$tmp/ecr" || missing="$missing ecr-public"
  grep -qx "$name" "$tmp/catalog" || missing="$missing catalog"
  if [ -n "$missing" ]; then
    echo "$name: missing$missing"
    status=1
  fi
done < "$tmp/all"

if [ "$status" -eq 0 ]; then
  echo "github $(wc -l < "$tmp/github" | tr -d ' '), ecr-public $(wc -l < "$tmp/ecr" | tr -d ' '), catalog $(wc -l < "$tmp/catalog" | tr -d ' '): every service has all three halves"
fi
exit "$status"
