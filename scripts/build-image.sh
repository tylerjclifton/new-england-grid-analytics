#!/bin/bash
# Build and push a component's Docker image to Artifact Registry.
#
# Usage:  scripts/build-image.sh <ingest|transform> <tag>
#
# Normally run by CI/CD (.github/workflows/ci.yml), which builds both with
# the commit as the tag and deploys them with `terraform apply -var image_tag=…`.

set -euo pipefail

COMPONENT="${1:?usage: $0 <ingest|transform> <version>}"
VERSION="${2:?usage: $0 <ingest|transform> <version>}"

PROJECT_ID="new-england-grid-analytics"
REGION="us-east1"

# Jobs live in the backend repository (a frontend one joins it with the dashboard)
case "${COMPONENT}" in
  ingest|transform) REPOSITORY="backend" ;;
  *) echo "Unknown component: ${COMPONENT}" >&2; exit 1 ;;
esac

IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${COMPONENT}:${VERSION}"

# Each component builds from its own folder (Dockerfile + requirements.txt)
cd "$(dirname "$0")/../${COMPONENT}"

echo "Building ${IMAGE}..."
docker build --platform linux/amd64 -t "${IMAGE}" .

echo "Pushing ${IMAGE}..."
docker push "${IMAGE}"

echo "✅ Pushed ${IMAGE}"
