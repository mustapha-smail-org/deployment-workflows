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
