# Changelog

All notable changes to the reusable workflows and composite actions in this
repository are documented here. Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Initial template system: `maven-verify`, `sonar-analysis`, `docker-build-push`
  composite actions.
- Reusable workflows `ci-pr.yml`, `ci-main.yml`, `ci-release.yml`.
- Render deployment adapter `deploy-render.yml`.
- `service-schema.json` and `environment-schema.json` contracts.
- Template guide, workflow contracts reference, and new-provider guide.
- `scripts/bootstrap-service.sh` to scaffold a new service's thin wrapper workflows.
- Node/Vite SPA support, alongside the existing Java/Spring stack:
  - Composite actions `node-verify` (install, lint, format-check, typecheck, test
    with coverage-threshold enforcement, build), `node-e2e` (Playwright suite
    against a production build), and `sonar-analysis-node` (SonarQube analysis for
    a Node/TypeScript project, structural config sourced from the caller's own
    `sonar-project.properties`).
  - Reusable workflows `ci-pr-node.yml` and `ci-main-node.yml`, mirroring
    `ci-pr-java.yml`/`ci-main-java.yml`'s shape (same permissions model, same
    `service-cd-repository`/`cd-environment` conventions, same
    default-branch dev-deploy dispatch). Both add an e2e stage (`run-e2e`,
    default `true` on PR / `false` on main) that runs in parallel with the
    lint/typecheck/coverage/Sonar stage.
  - `ci-release.yml`, `deploy-render.yml`, and `docker-build-push` are unchanged
    and shared by both stacks — none of the three has stack-specific logic.
  - `scripts/bootstrap-service.sh`: new `--stack java|node` flag (default `java`,
    so existing invocations are unaffected), plus `--node-version` and
    `--coverage-threshold` for the Node path.
  - `docs/TEMPLATE_GUIDE.md` restructured with parallel Java (§1a/2a/3a) and Node
    (§1b/2b/3b) subsections, including the runtime-configuration pattern a Vite
    SPA needs in place of build-time `VITE_*` baking to preserve the
    build-once-promote-everywhere model.
  - `docs/WORKFLOW_CONTRACTS.md` updated with full input/output reference for
    every new action and workflow.

### Added
- `ci-main-java.yml`: new `skip-cd-dispatch` input (boolean, default `false`).
  Set `true` as a temporary bridge for a service whose `<service-name>-cd` repo
  doesn't exist yet — without it, `deploy-dev` fails trying to dispatch a
  workflow run in a nonexistent repo (`api-gateway` and `discovery-server` hit
  this after onboarding, since neither has a `-cd` repo yet). Every other
  input is unaffected; `verify` and `image` still run normally.

### Changed — BREAKING
- Renamed `ci-pr.yml` → `ci-pr-java.yml` and `ci-main.yml` → `ci-main-java.yml`,
  and `.github/actions/sonar-analysis` → `.github/actions/sonar-analysis-maven`,
  to sit symmetrically alongside `ci-pr-node.yml`/`ci-main-node.yml`/
  `sonar-analysis-node` now that a second stack exists. Their `name:` fields also
  gained a `(Java)`/`(Node)` suffix for symmetry in the Actions UI.
  `ci-release.yml`, `deploy-render.yml`, and `docker-build-push` are unaffected —
  none of the three is stack-specific, so neither name nor behavior changed.
  **Migration:** every caller's `pr.yml`/`main.yml` must update its `uses:` line
  (`ci-pr.yml@main` → `ci-pr-java.yml@main`, `ci-main.yml@main` →
  `ci-main-java.yml@main`) — done in the same change for all four Java callers
  (`data-ingestion`, `catalog-service`, `api-gateway`, `discovery-server`).
  `scripts/bootstrap-service.sh` and the docs were updated to the new names in
  the same commit.
