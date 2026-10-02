#!/bin/sh
# Every claim under claims/<team>/ must have a catalog entity under
# backstage/catalog/resources/<team>/ with the same file name, and the
# reverse. Each template writes both in one pull request; this check stops a
# teardown that removes only one of them. Files are <name>.yaml for a Database
# and <name>.webservice.yaml for a WebService; XR names cannot contain dots,
# so the two never collide. Directories starting with an underscore hold
# platform entities and are skipped.
#
# An entity written by the service or deploy template (it carries the
# platform.jordandesigns.io/repository annotation) also mirrors every claim
# value as an annotation, because the deploy template re-renders the claim
# from them (ADR-0024). For those, each value must match the claim, so a
# claim edited by hand cannot drift from what the next deploy would render.
# Both files are template output with one key per line, so plain text
# extraction is enough; a value that cannot be read counts as a mismatch.
set -eu

status=0

# claim_value <file> <key>: value of a two-space-indented spec key.
claim_value() {
  sed -n "s/^  $2: *//p" "$1" | head -n 1
}

# claim_label <file>: the cloud label under compositionSelector.
claim_label() {
  sed -n 's/^ *platform\.jordandesigns\.io\/cloud: *//p' "$1" | head -n 1
}

# annotation <file> <key>: value of platform.jordandesigns.io/<key>, quotes removed.
annotation() {
  sed -n "s/^    platform\.jordandesigns\.io\/$2: *//p" "$1" | head -n 1 | sed 's/^"\(.*\)"$/\1/'
}

compare() {
  if [ -z "$3" ] || [ "$3" != "$4" ]; then
    echo "$1: $2 is '$4' in the claim but '$3' on the entity"
    status=1
  fi
}

check_values() {
  claim=$1
  entity=$2
  grep -q '^    platform\.jordandesigns\.io/repository:' "$entity" || return 0
  compare "$entity" image "$(annotation "$entity" image)" "$(claim_value "$claim" image)"
  compare "$entity" port "$(annotation "$entity" port)" "$(claim_value "$claim" port)"
  compare "$entity" healthPath "$(annotation "$entity" health-path)" "$(claim_value "$claim" healthPath)"
  compare "$entity" size "$(annotation "$entity" size)" "$(claim_value "$claim" size)"
  compare "$entity" visibility "$(annotation "$entity" visibility)" "$(claim_value "$claim" visibility)"
  compare "$entity" maxInstances "$(annotation "$entity" max-instances)" "$(claim_value "$claim" maxInstances)"
  compare "$entity" environment "$(annotation "$entity" environment)" "$(claim_value "$claim" environment)"
  compare "$entity" costCenter "$(annotation "$entity" cost-center)" "$(claim_value "$claim" costCenter)"
  compare "$entity" owner "$(annotation "$entity" requested-by)" "$(claim_value "$claim" owner)"
  compare "$entity" cloud "$(annotation "$entity" cloud)" "$(claim_label "$claim")"
  compare "$entity" namespace "$(annotation "$entity" team)" "$(claim_value "$claim" namespace)"
}

for claim in claims/*/*.yaml; do
  [ -e "$claim" ] || continue
  team=$(basename "$(dirname "$claim")")
  entity="backstage/catalog/resources/$team/$(basename "$claim")"
  if [ ! -f "$entity" ]; then
    echo "missing catalog entity $entity for $claim"
    status=1
    continue
  fi
  check_values "$claim" "$entity"
done

for entity in backstage/catalog/resources/*/*.yaml; do
  [ -e "$entity" ] || continue
  team=$(basename "$(dirname "$entity")")
  case "$team" in _*) continue ;; esac
  claim="claims/$team/$(basename "$entity")"
  if [ ! -f "$claim" ]; then
    echo "catalog entity $entity has no claim $claim"
    status=1
  fi
done

exit "$status"
