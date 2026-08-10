# deployment-workflows

Centralized, reusable CI/CD templates for CityPulse services. This repository owns
the *behavior* (how builds run, how quality gates are enforced, how deployments
happen); application repos and service CD repos own only their own *configuration*.

Implements the "build once, promote the same immutable artifact through every
environment" model described in `docs/CI_CD/cicd_architecture_spec.md` in the main
CityPulse repo.

## What's here

```
.github/
  actions/
    maven-verify/        Maven build + tests + JaCoCo coverage check
    sonar-analysis/       SonarQube analysis + quality gate
    docker-build-push/    Build & push an image tagged by commit SHA
  workflows/
    ci-pr.yml              Reusable: pull-request verification (no publish)
    ci-main.yml             Reusable: default-branch build, image publish, dev deploy dispatch
    ci-release.yml          Reusable: semantic tag promotion (re-tags existing digest, no rebuild)
    deploy-render.yml       Reusable: Render deployment adapter
contracts/
  service-schema.json       Schema for a service CD repo's service.yaml
  environment-schema.json   Schema for a service CD repo's environments/*.yaml
docs/
  TEMPLATE_GUIDE.md          How to onboard a new service
  WORKFLOW_CONTRACTS.md      Full input/output reference for every action/workflow
  ADDING_NEW_PROVIDER.md     How to add a new deployment adapter
scripts/
  bootstrap-service.sh       Scaffold a new service repo's thin wrapper workflows
```

## Quick start (using these templates from a service repo)

See `docs/TEMPLATE_GUIDE.md` for the full walkthrough. In short, a service repo adds
three ~15-line workflow files that each `uses:` one of the reusable workflows above,
and its `-cd` repo adds one `deploy.yml` that `uses: deploy-render.yml`. No Maven,
Sonar, or Docker logic is duplicated per service.

Reference implementation: `data-ingestion` (application) +
`data-ingestion-cd` (desired state).

## Design principles

- **Centralize behavior, decentralize configuration.** Provider and build logic
  lives here; services pass only inputs (service name, thresholds, IDs).
- **Immutable artifacts.** Deployments always resolve to an OCI digest
  (`sha256:...`), never a mutable tag like `main` or `latest`.
- **Build once, deploy many.** `ci-release.yml` never rebuilds — it re-tags the
  digest that `ci-main.yml` already published for that commit.
- **Least privilege.** Cross-repo dispatch uses a scoped GitHub App token, not a
  broad PAT; each workflow declares only the `permissions` it needs.

## Versioning

During the pilot phase, callers reference this repo with `@main`. Once more than one
service depends on it, pin production-critical callers to a commit SHA and track
changes in `CHANGELOG.md`.
