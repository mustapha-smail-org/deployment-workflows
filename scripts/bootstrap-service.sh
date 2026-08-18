#!/usr/bin/env bash
#
# Scaffold the thin wrapper CI workflows for a new service repo that consumes
# the reusable templates in this repository. Run from inside the target
# service repo's working copy (not from deployment-workflows).
#
# Usage (Java/Spring, the default):
#   ./bootstrap-service.sh --service-path <path> \
#       --service-name <service-name> \
#       --sonar-org <org> \
#       --java-version 21 \
#       --jacoco-threshold 70
#
# Usage (Node/Vite SPA):
#   ./bootstrap-service.sh --service-path <path> \
#       --service-name <service-name> \
#       --sonar-org <org> \
#       --stack node \
#       --node-version 22 \
#       --coverage-threshold 70

set -euo pipefail

TEMPLATES_REPO="mustapha-smail-org/deployment-workflows"
TEMPLATES_REF="main"

STACK="java"
JAVA_VERSION="21"
JACOCO_THRESHOLD="70"
NODE_VERSION="22"
COVERAGE_THRESHOLD="70"
SERVICE_NAME=""
SERVICE_PATH=""
SONAR_KEY=""
SONAR_NAME=""
SONAR_ORG=""
CD_REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service-path) SERVICE_PATH="$2"; shift 2 ;;
    --service-name) SERVICE_NAME="$2"; shift 2 ;;
    --sonar-org) SONAR_ORG="$2"; shift 2 ;;
    --stack) STACK="$2"; shift 2 ;;
    --java-version) JAVA_VERSION="$2"; shift 2 ;;
    --jacoco-threshold) JACOCO_THRESHOLD="$2"; shift 2 ;;
    --node-version) NODE_VERSION="$2"; shift 2 ;;
    --coverage-threshold) COVERAGE_THRESHOLD="$2"; shift 2 ;;
    --cd-repo) CD_REPO="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$STACK" != "java" && "$STACK" != "node" ]]; then
  echo "::error::--stack must be 'java' or 'node', got '${STACK}'" >&2
  exit 1
fi

SONAR_KEY="${SONAR_ORG}_${SERVICE_NAME}"
SONAR_NAME="${SERVICE_NAME}"
if [[ -n "$CD_REPO" && "$CD_REPO" != *"/"* ]]; then
  echo "::error::--cd-repo must be in \"[HOST/]OWNER/REPO\" format, got \"${CD_REPO}\" (missing the owner prefix)" >&2
  exit 1
fi

if [[ -z "$SERVICE_PATH" || -z "$SERVICE_NAME" || -z "$SONAR_ORG" ]]; then
  echo "Usage: $0 --service-path <path> --service-name <name> --sonar-org <org> [--stack java|node] [--java-version 21] [--jacoco-threshold 70] [--node-version 22] [--coverage-threshold 70] [--cd-repo <owner>/<repo>]" >&2
  exit 1
fi

cd "$SERVICE_PATH"
git checkout main
git pull origin main
git checkout -b ci-bootstrap || git checkout ci-bootstrap

mkdir -p .github/workflows

CD_REPO_LINE=""
if [[ -n "$CD_REPO" ]]; then
  CD_REPO_LINE="      service-cd-repository: ${CD_REPO}"$'\n'
fi

if [[ "$STACK" == "java" ]]; then

cat > .github/workflows/pr.yml <<EOF
name: PR
on:
  pull_request:
    branches: [main]

jobs:
  ci:
    permissions:
      contents: read
    uses: ${TEMPLATES_REPO}/.github/workflows/ci-pr.yml@${TEMPLATES_REF}
    with:
      java-version: '${JAVA_VERSION}'
      sonar-project-key: ${SONAR_KEY}
      sonar-project-name: '${SONAR_NAME}'
      sonar-organization: ${SONAR_ORG}
      jacoco-threshold: '${JACOCO_THRESHOLD}'
    secrets:
      sonar-token: \${{ secrets.SONAR_TOKEN }}
EOF

cat > .github/workflows/main.yml <<EOF
name: Main
on:
  push:
    branches: [main]

jobs:
  ci:
    permissions:
      contents: read
      packages: write
      id-token: write
    uses: ${TEMPLATES_REPO}/.github/workflows/ci-main.yml@${TEMPLATES_REF}
    with:
      service-name: ${SERVICE_NAME}
      java-version: '${JAVA_VERSION}'
      sonar-project-key: ${SONAR_KEY}
      sonar-project-name: '${SONAR_NAME}'
      sonar-organization: ${SONAR_ORG}
      jacoco-threshold: '${JACOCO_THRESHOLD}'
      automation-app-id: \${{ vars.AUTOMATION_APP_ID }}
${CD_REPO_LINE}    secrets:
      sonar-token: \${{ secrets.SONAR_TOKEN }}
      automation-app-private-key: \${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
EOF

else # node

cat > .github/workflows/pr.yml <<EOF
name: PR
on:
  pull_request:
    branches: [main]

jobs:
  ci:
    permissions:
      contents: read
    uses: ${TEMPLATES_REPO}/.github/workflows/ci-pr-node.yml@${TEMPLATES_REF}
    with:
      node-version: '${NODE_VERSION}'
      sonar-project-key: ${SONAR_KEY}
      sonar-project-name: '${SONAR_NAME}'
      sonar-organization: ${SONAR_ORG}
      coverage-threshold: '${COVERAGE_THRESHOLD}'
    secrets:
      sonar-token: \${{ secrets.SONAR_TOKEN }}
EOF

cat > .github/workflows/main.yml <<EOF
name: Main
on:
  push:
    branches: [main]

jobs:
  ci:
    permissions:
      contents: read
      packages: write
      id-token: write
    uses: ${TEMPLATES_REPO}/.github/workflows/ci-main-node.yml@${TEMPLATES_REF}
    with:
      service-name: ${SERVICE_NAME}
      node-version: '${NODE_VERSION}'
      sonar-project-key: ${SONAR_KEY}
      sonar-project-name: '${SONAR_NAME}'
      sonar-organization: ${SONAR_ORG}
      coverage-threshold: '${COVERAGE_THRESHOLD}'
      automation-app-id: \${{ vars.AUTOMATION_APP_ID }}
${CD_REPO_LINE}    secrets:
      sonar-token: \${{ secrets.SONAR_TOKEN }}
      automation-app-private-key: \${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
EOF

fi

# release.yml uses ci-release.yml, which is stack-agnostic — identical either way.
cat > .github/workflows/release.yml <<EOF
name: Release
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'

jobs:
  release:
    permissions:
      contents: read
      packages: write
      id-token: write
    uses: ${TEMPLATES_REPO}/.github/workflows/ci-release.yml@${TEMPLATES_REF}
    with:
      service-name: ${SERVICE_NAME}
      automation-app-id: \${{ vars.AUTOMATION_APP_ID }}
${CD_REPO_LINE}    secrets:
      automation-app-private-key: \${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
EOF

echo "Created .github/workflows/{pr,main,release}.yml for ${SERVICE_NAME} (stack: ${STACK}) on branch ci-bootstrap."
echo "Next steps:"
if [[ "$STACK" == "java" ]]; then
  echo "  1. Add a Dockerfile and sonar-project.properties if missing."
  echo "  2. Ensure pom.xml has the JaCoCo coverage-check bound to verify (see docs/TEMPLATE_GUIDE.md §3a)."
else
  echo "  1. Add a Dockerfile (nginx-based reference: TEMPLATE_GUIDE.md §1b) and sonar-project.properties."
  echo "  2. Ensure package.json has lint/format:check/typecheck/test:coverage/build scripts, and"
  echo "     vitest.config.ts's coverage.reporter includes 'lcov' and 'json-summary' (see docs/TEMPLATE_GUIDE.md §3b)."
fi
echo "  3. Set repo secrets: SONAR_TOKEN, AUTOMATION_APP_PRIVATE_KEY."
echo "     Set repo variable (not secret): AUTOMATION_APP_ID."
echo "  4. Create the <service>-cd repository if it doesn't exist yet."
