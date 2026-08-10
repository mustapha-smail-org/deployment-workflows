# Workflow & Action Contracts

Stable input/output reference for everything in this repository. Treat this file as
the source of truth when wiring a new service or modifying a template — update it in
the same PR as any input/output change.

Breaking changes (removing an input, changing a type, changing default behavior)
require a major version note in `CHANGELOG.md` and, for production-critical callers,
advance notice before merging.

---

## Composite Actions

### `.github/actions/maven-verify`

Runs `mvnw clean verify` and extracts JaCoCo line coverage.

| Input | Required | Default | Notes |
|---|---|---|---|
| `java-version` | no | `21` | |
| `java-distribution` | no | `temurin` | |
| `jacoco-threshold` | no | `70` | Percentage (0-100). Passed to Maven as `-Djacoco.line.coverage.minimum=<threshold/100>`. Service's `pom.xml` must consume this property (see TEMPLATE_GUIDE.md). |
| `working-directory` | no | `.` | Use for multi-module repos where the service lives in a subdirectory. |

| Output | Description |
|---|---|
| `coverage-percentage` | Line coverage percentage as reported by JaCoCo XML. |
| `test-results-path` | Path to `target/surefire-reports`. |

Failure mode: the step fails (non-zero exit) if `mvnw verify` fails, which includes
JaCoCo threshold violations because the check is bound to the `verify` phase.

---

### `.github/actions/sonar-analysis`

Runs the Sonar Maven plugin by fully-qualified coordinates
(`org.sonarsource.scanner.maven:sonar-maven-plugin:<version>:sonar`) and blocks on
the quality gate. Deliberately **not** invoked via the `sonar:` prefix shorthand —
that shorthand only resolves if the plugin is already declared in the calling
project's `pom.xml`, which would force every onboarded service to add it. Calling by
full coordinates keeps this a zero-pom.xml-changes template.

| Input | Required | Default |
|---|---|---|
| `sonar-host-url` | no | `https://sonarcloud.io` |
| `sonar-token` | **yes** | — |
| `sonar-project-key` | **yes** | — |
| `sonar-project-name` | **yes** | — |
| `sonar-organization` | no | `''` (omit `-Dsonar.organization` if blank) |
| `java-version` | no | `21` |
| `working-directory` | no | `.` |
| `sonar-plugin-version` | no | `5.7.0.6970` (latest stable on Maven Central at time of writing) |

| Output | Description |
|---|---|
| `quality-gate-status` | `PASSED` or `FAILED`. The step also fails the job on `FAILED`. |

---

### `.github/actions/docker-build-push`

Builds and pushes an image tagged by commit SHA (plus optional extra mutable tags).

| Input | Required | Default |
|---|---|---|
| `service-name` | **yes** | — |
| `registry` | no | `ghcr.io` |
| `registry-namespace` | no | repository owner (lowercased) |
| `image-tag-sha` | **yes** | e.g. `sha-abc1234` |
| `registry-username` | **yes** | — |
| `registry-password` | **yes** | — |
| `dockerfile-path` | no | `./Dockerfile` |
| `build-context` | no | `.` |
| `extra-tags` | no | `''` — comma-separated mutable tags, e.g. `main,latest` |

| Output | Description |
|---|---|
| `image-digest` | Immutable `sha256:...` digest. This is the authoritative deployment reference — never the mutable tags. |
| `image-repository` | Full repo path, e.g. `ghcr.io/org/service`. |
| `image-tags` | All tags applied to the push, comma-separated. |

---

## Reusable Workflows

### `.github/workflows/ci-pr.yml`

Trigger: called from a service's `pull_request` workflow. **Never publishes an
image and never touches deployment credentials.**

**Inputs:** `java-version`, `sonar-project-key` (required), `sonar-project-name`
(required), `sonar-organization`, `sonar-host-url`, `jacoco-threshold`,
`working-directory`.

**Secrets:** `sonar-token` (required).

**Outputs:** `coverage-percentage`.

**Permissions granted:** `contents: read` only.

---

### `.github/workflows/ci-main.yml`

Trigger: called from a service's `push: branches: [main]` workflow.

Sequence: `verify` (maven-verify + sonar-analysis) → `image` (docker-build-push,
tag `sha-<short-sha>`) → `deploy-dev` (GitHub App token → `gh workflow run deploy.yml`
in the service's CD repo, environment defaults to `dev`).

**Inputs:** `service-name` (required), `java-version`, `sonar-project-key`
(required), `sonar-project-name` (required), `sonar-organization`, `sonar-host-url`,
`jacoco-threshold`, `working-directory`, `image-registry`, `dockerfile-path`,
`automation-app-id` (required), `service-cd-repository` (defaults to
`<owner>/<service-name>-cd`), `cd-environment` (default `dev`).

**Secrets:** `sonar-token` (required), `automation-app-private-key` (required).

**Outputs:** `image-digest`, `image-tags`.

**Permissions granted:** `contents: read`, `packages: write`, `id-token: write`.

**Concurrency:** `ci-main-<service-name>`, does not cancel in-progress runs (a
default-branch build should always complete and record its artifact).

---

### `.github/workflows/ci-release.yml`

Trigger: called from a service's `push: tags: ['v*.*.*']` workflow.

Sequence: `resolve-tag` (verify tag is reachable from `main`) → `promote` (resolve
the digest already pushed for that commit's `sha-<short-sha>` tag via `crane digest`,
then `crane tag` the semver onto the **same digest** — no rebuild) →
`dispatch-promotion` (GitHub App token → `gh workflow run deploy.yml` in the CD repo,
environment defaults to `staging`).

**Inputs:** `service-name` (required), `image-registry`, `automation-app-id`
(required), `service-cd-repository`, `cd-environment` (default `staging`),
`default-branch` (default `main`).

**Secrets:** `automation-app-private-key` (required).

**Outputs:** `image-digest`.

**Invariant enforced:** if the tagged commit isn't reachable from `default-branch`,
or the `sha-<short-sha>` image doesn't already exist in the registry, the job fails
loudly rather than silently rebuilding.

---

### `.github/workflows/deploy-render.yml`

Trigger: called from a service CD repo's `deploy.yml`, after it has already updated
and committed the target `environments/<env>.yaml`.

Sequence: validate inputs → trigger Render deploy via API with the image digest →
poll for `live` status (fail on `build_failed`/`update_failed`/`canceled`/timeout) →
optional HTTP health check → emit job summary.

**Inputs:** `service-name` (required), `environment` (required), `image-repository`
(required), `image-digest` (required, must match `^sha256:[a-f0-9]{64}$`),
`service-id` (required, Render service ID), `health-check-url` (optional — skips the
health step if blank), `health-check-path` (default
`/actuator/health/readiness`), `deploy-timeout-seconds` (default `300`).

**Secrets:** `render-api-key` (required).

**Outputs:** `deployment-status` (`success`/`failed`), `deployment-id`,
`deployment-url`.

**Concurrency:** `deploy-<service-name>-<environment>`. Cancels in-progress runs only
for `dev` (newest commit wins); `staging`/`production` deployments queue instead of
being interrupted.

---

## Naming & Versioning

- Reference this repo with `@main` during the pilot phase. Once multiple services
  depend on it, pin production-critical callers to a commit SHA or a released tag
  (see `CHANGELOG.md`) instead of a moving branch.
- All third-party actions used inside this repo are pinned to a full commit SHA.
