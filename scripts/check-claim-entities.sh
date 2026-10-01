#!/bin/sh
# Every Database claim under claims/<team>/ must have a catalog Resource entity
# under backstage/catalog/resources/<team>/ with the same file name, and the
# reverse. The Database template writes both in one pull request; this check
# stops a teardown that removes only one of them. Directories starting with an
# underscore hold platform entities and are skipped.
set -eu

status=0

for claim in claims/*/*.yaml; do
  [ -e "$claim" ] || continue
  team=$(basename "$(dirname "$claim")")
  entity="backstage/catalog/resources/$team/$(basename "$claim")"
  if [ ! -f "$entity" ]; then
    echo "missing catalog entity $entity for $claim"
    status=1
  fi
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
