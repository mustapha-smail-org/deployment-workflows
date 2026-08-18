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
    `ci-pr.yml`/`ci-main.yml`'s shape (same permissions model, same
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
