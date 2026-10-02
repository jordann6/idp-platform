#!/bin/sh
# Prints one key=true|false line per Terraform root for $GITHUB_OUTPUT, so the
# Guardrails workflow runs the six tf-ci jobs of a root only when it changed.
# EVENT is the GitHub event name; PR_BASE and PUSH_BEFORE are the commits to
# diff against. Everything runs on a manual dispatch, on a push with no
# previous commit, when the base cannot be read, and when .github changes.
# A new root must be added here and as a job in guardrails.yml.
set -eu

roots="
aws_oidc_issuer=bootstrap/aws/oidc-issuer
aws_crossplane_auth=bootstrap/aws/crossplane-auth
aws_budget=bootstrap/aws/budget
aws_network=bootstrap/aws/network
aws_ingress=bootstrap/aws/ingress
azure_crossplane_auth=bootstrap/azure/crossplane-auth
azure_budget=bootstrap/azure/budget
azure_network=bootstrap/azure/network
gcp_project=bootstrap/gcp/project
gcp_crossplane_auth=bootstrap/gcp/crossplane-auth
gcp_budget=bootstrap/gcp/budget
gcp_network=bootstrap/gcp/network
gcp_web=bootstrap/gcp/web
"

zero=0000000000000000000000000000000000000000
case "${EVENT:-}" in
  pull_request) base=${PR_BASE:-} ;;
  push) base=${PUSH_BEFORE:-} ;;
  *) base= ;;
esac

all=false
if [ -z "$base" ] || [ "$base" = "$zero" ]; then
  all=true
elif ! changed=$(git diff --name-only "$base" HEAD 2>/dev/null); then
  all=true
elif printf '%s\n' "$changed" | grep -q '^\.github/'; then
  all=true
fi

for entry in $roots; do
  key=${entry%%=*}
  dir=${entry#*=}
  if [ "$all" = true ] || printf '%s\n' "$changed" | grep -q "^$dir/"; then
    echo "$key=true"
  else
    echo "$key=false"
  fi
done
