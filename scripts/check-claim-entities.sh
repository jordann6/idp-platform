#!/bin/sh
# Every claim under claims/<team>/ must have a catalog entity under
# backstage/catalog/resources/<team>/ with the same file name, and the
# reverse. Each template writes both in one pull request; this check stops a
# teardown that removes only one of them. Files are <name>.yaml for a Database
# and <name>.webservice.yaml for a WebService; XR names cannot contain dots,
# so the two never collide. Directories starting with an underscore hold
# platform entities and are skipped.
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
