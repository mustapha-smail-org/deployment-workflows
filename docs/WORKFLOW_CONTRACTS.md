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

### `.github/actions/sonar-analysis-maven`

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

### `.github/actions/node-verify`

Installs dependencies, runs lint/format-check/typecheck, runs the test command with
coverage, enforces the coverage threshold, and builds. The Node analogue of
`maven-verify`.

| Input | Required | Default | Notes |
|---|---|---|---|
| `node-version` | no | `22` | |
| `working-directory` | no | `.` | |
| `coverage-threshold` | no | `70` | Percentage (0-100). Unlike `maven-verify`, this is **not** passed into the test command — it's enforced by this action after the run reading `coverage/coverage-summary.json`. See TEMPLATE_GUIDE.md §3b. |
| `install-command` | no | `npm ci` | |
| `lint-command` | no | `npm run lint` | Set to `''` to skip. |
| `format-check-command` | no | `npm run format:check` | Set to `''` to skip. |
| `typecheck-command` | no | `npm run typecheck` | Set to `''` to skip. |
| `test-command` | no | `npm run test:coverage` | Must emit `coverage/coverage-summary.json` (this action's threshold check) and `coverage/lcov.info` (`sonar-analysis-node`). |
| `build-command` | no | `npm run build` | Set to `''` to skip. |

| Output | Description |
|---|---|
| `coverage-percentage` | Line coverage percentage from `coverage/coverage-summary.json`'s `total.lines.pct`. |
| `dist-path` | `<working-directory>/dist`. |

Failure mode: fails if any gate command exits non-zero, or if
`coverage-percentage < coverage-threshold`, or if `coverage-summary.json` is
missing (a misconfigured reporter, not silently treated as 0%).

---

### `.github/actions/node-e2e`

Installs Playwright browsers (cached by `@playwright/test` version resolved from
`package-lock.json`) and runs the e2e suite. Does not build the app itself — the
reference `playwright.config.ts` `webServer` builds and serves a production bundle
as part of `test-command`, so this action stays test-runner-agnostic.

| Input | Required | Default | Notes |
|---|---|---|---|
| `node-version` | no | `22` | |
| `working-directory` | no | `.` | |
| `install-command` | no | `npm ci` | |
| `browsers` | no | `chromium webkit` | Space-separated. Must match the projects declared in `playwright.config.ts`. |
| `test-command` | no | `npm run test:e2e` | |
| `report-path` | no | `playwright-report` | Uploaded as an artifact on failure only. |
| `results-path` | no | `test-results` | Uploaded as an artifact on failure only. |

No outputs. Failure mode: fails if `test-command` exits non-zero; uploads the
Playwright HTML report and `test-results/` (traces, screenshots) as artifacts when
it does, for post-mortem without re-running.

---

### `.github/actions/sonar-analysis-node`

Runs `SonarSource/sonarqube-scan-action` and blocks on the quality gate. Unlike
`sonar-analysis-maven` (Java), structural project config (`sonar.sources`, `sonar.tests`,
`sonar.exclusions`, `sonar.javascript.lcov.reportPaths`) is **not** passed as CLI
args here — it lives in a `sonar-project.properties` file in the target repo,
because there's no Maven-equivalent single entry point (`pom.xml`) this action could
read those settings from generically.

| Input | Required | Default |
|---|---|---|
| `sonar-host-url` | no | `https://sonarcloud.io` |
| `sonar-token` | **yes** | — |
| `sonar-project-key` | **yes** | — |
| `sonar-project-name` | **yes** | — |
| `sonar-organization` | no | `''` (omit `-Dsonar.organization` if blank) |
| `working-directory` | no | `.` — passed as `projectBaseDir`. |

| Output | Description |
|---|---|
| `quality-gate-status` | `PASSED` or `FAILED`. The step also fails the job on `FAILED`. |

**Must run in the same job as `node-verify`, after it:** this action reads
`coverage/lcov.info` off the runner's local disk (produced by `node-verify`'s
`test-command`). Jobs run on separate runners with no shared filesystem, so
splitting these two across jobs doesn't error — Sonar just silently reports 0%
coverage. `ci-pr-node.yml` / `ci-main-node.yml` already sequence this correctly
within one job; preserve that if you extend either workflow.

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

### `.github/workflows/ci-pr-java.yml`

Trigger: called from a service's `pull_request` workflow. **Never publishes an
image and never touches deployment credentials.**

**Inputs:** `java-version`, `sonar-project-key` (required), `sonar-project-name`
(required), `sonar-organization`, `sonar-host-url`, `jacoco-threshold`,
`working-directory`.

**Secrets:** `sonar-token` (required).

**Outputs:** `coverage-percentage`.

**Permissions granted:** `contents: read` only.

---

### `.github/workflows/ci-main-java.yml`

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

### `.github/workflows/ci-pr-node.yml`

Trigger: called from a service's `pull_request` workflow. **Never publishes an
image and never touches deployment credentials.** Node analogue of `ci-pr-java.yml`.

Sequence: `verify` (node-verify + sonar-analysis-node, one job) and `e2e`
(node-e2e) run **in parallel** — the e2e suite doesn't depend on the Sonar quality
gate, so there's no reason to queue it behind that poll.

**Inputs:** `node-version`, `sonar-project-key` (required), `sonar-project-name`
(required), `sonar-organization`, `sonar-host-url`, `coverage-threshold`,
`working-directory`, `run-e2e` (default `true`), `e2e-browsers`.

**Secrets:** `sonar-token` (required).

**Outputs:** `coverage-percentage`.

**Permissions granted:** `contents: read` only.

---

### `.github/workflows/ci-main-node.yml`

Trigger: called from a service's `push: branches: [main]` workflow. Node analogue
of `ci-main-java.yml`.

Sequence: `verify` (node-verify + sonar-analysis-node) and `e2e` (node-e2e, if
`run-e2e`) → `image` (docker-build-push, tag `sha-<short-sha>`, waits on both
`verify` and `e2e` — see the `if:` gate below) → `deploy-dev` (GitHub App token →
`gh workflow run deploy.yml` in the service's CD repo, environment defaults to
`dev`).

**Inputs:** `service-name` (required), `node-version`, `sonar-project-key`
(required), `sonar-project-name` (required), `sonar-organization`, `sonar-host-url`,
`coverage-threshold`, `working-directory`, `run-e2e` (default **`false`** — unlike
`ci-pr-node.yml`; a default-branch build was already gated by the PR's e2e run, so
re-running it here would only add latency ahead of the dev deploy), `e2e-browsers`,
`image-registry`, `dockerfile-path`, `automation-app-id` (required),
`service-cd-repository` (defaults to `<owner>/<service-name>-cd`), `cd-environment`
(default `dev`).

**Secrets:** `sonar-token` (required), `automation-app-private-key` (required).

**Outputs:** `image-digest`, `image-tags`.

**Permissions granted:** `contents: read`, `packages: write`, `id-token: write`.

**Concurrency:** `ci-main-<service-name>`, does not cancel in-progress runs — same
convention as `ci-main-java.yml`.

**`image` job's `if:` gate:** `always() && needs.verify.result == 'success' &&
(needs.e2e.result == 'success' || needs.e2e.result == 'skipped')`. Needed because
`e2e` is conditional on `run-e2e`; when it's `false` the job is `skipped`, not
`success`, so a plain `needs.e2e.result == 'success'` check would block the image
build entirely whenever e2e is turned off.

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

**Permissions granted:** `contents: read`, `packages: write`, `id-token: write`.
`packages: write` — not `read` — despite never rebuilding: `crane tag` performs a
manifest `PUT` to attach the semver tag to the existing digest, and GHCR requires
write/push permission for any tag-creating operation regardless of whether new
blob content is uploaded. `packages: read` fails at runtime (not parse time) with
`DENIED: installation not allowed to Write organization package`.

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

Deliberately does **not** know anything about config files, secrets, or per-service
config — this workflow is purely a generic image-deployment adapter, identical for
every caller regardless of how many secrets a service has. See "Externalized app
config" below and `TEMPLATE_GUIDE.md` for where that concern actually lives.

**Inputs:** `service-name` (required), `environment` (required), `image-repository`
(required), `image-digest` (required, must match `^sha256:[a-f0-9]{64}$`),
`health-check-url` (optional — skips the health step if blank), `health-check-path`
(default `/actuator/health/readiness`), `deploy-timeout-seconds` (default `300`).

**Secrets:** `render-api-key` (required), `service-id` (required, the Render service
ID). `service-id` is a **secrets-block** input, not a plain input — see the
"secret job outputs" trap below.

**Outputs:** `deployment-status` (`success`/`failed`), `deployment-id`,
`deployment-url`.

**Concurrency:** `deploy-<service-name>-<environment>`. Cancels in-progress runs only
for `dev` (newest commit wins); `staging`/`production` deployments queue instead of
being interrupted.

**Concurrency deadlock trap:** since `deploy-render.yml` is called as a job from a
service CD repo's own `deploy.yml`, that caller's top-level `concurrency:` group
**must not** resolve to the same string as `deploy-<service-name>-<environment>`.
If it does, the top-level run ends up waiting on a concurrency slot it already
holds via its own `deploy` job — GitHub Actions detects this and cancels the run
with `Canceling since a deadlock was detected`. Give the caller's own group a
different prefix, e.g. `cd-state-<service-name>-<environment>` (see
`data-ingestion-cd/.github/workflows/deploy.yml` for the reference).

**Secret job outputs get blanked, not passed through:** if a value is resolved in
one job (e.g. picking the right `RENDER_SERVICE_ID_*` secret based on
`inputs.environment` inside a `run:` step, then exposing it as a job `output`) and
that output is then passed into a *different* job's `with:`/`secrets:` block for a
`uses:` reusable-workflow call, GitHub Actions silently replaces it with an empty
string the moment the value has been masked (via `::add-mask::`, or automatically
because it originated from `secrets`). This is intentional secret-hygiene behavior,
not a bug — job outputs are visible in the UI/API, so GitHub won't let a masked
value flow through them into another job's visible "Inputs" section. The symptom is
confusing: the producing step succeeds with no error, but the consuming job's
"Inputs" log shows the value blank (e.g. `service-id: `), and the downstream step
then fails with something like `service-id is required`.

**The fix:** never route a secret through a step output → job output → another
job's `with:`/`secrets:` chain. Do any environment-to-secret selection as a pure
workflow *expression*, evaluated at parse time before any job runs — e.g. in the
caller's own `secrets:` block:
```yaml
secrets:
  service-id: ${{ inputs.environment == 'dev' && secrets.RENDER_SERVICE_ID_DEV || inputs.environment == 'staging' && secrets.RENDER_SERVICE_ID_STAGING || secrets.RENDER_SERVICE_ID_PRODUCTION }}
```
This `&&`/`||` chain is GitHub Actions' idiomatic substitute for a ternary/switch
(there's no native `if` expression). Keep it on one line — folded YAML block
scalars (`>-`) can leave embedded newlines inside the `${{ }}` expression when the
content is indented deeper than the scalar's base level, which is an unnecessary
risk for something this easy to keep on one line.

---

## Externalized App Config

Not a reusable workflow — a pattern each service's own CD repo implements itself,
because the number and names of secrets a service needs is unbounded and inherently
service-specific. `deploy-render.yml` deliberately has no knowledge of this at all.

**The constraint driving the design:** GitHub Actions never lets a script look up
`secrets.<name>` using a name discovered at runtime (e.g. by reading a placeholder
out of a file) — every secret a script touches must be named explicitly in a
workflow file, at authoring time. There's no way around this, so the goal is to
make the *unavoidable* per-secret enumeration as cheap as possible, and keep
everything else generic.

**The pattern** (reference implementation: `data-ingestion-cd/config/*.yaml` +
`data-ingestion-cd/.github/workflows/deploy.yml`'s `push-config` job):

1. A tracked, per-environment config file (e.g. `config/dev.yaml`) holds normal
   operational config directly, and represents secret values with a
   `%%SECRET:NAME%%` token instead of a real value.
2. A dedicated job in the service's own `deploy.yml` declares one `env:` line per
   secret the service needs — `SECRET_KAFKA_USERNAME: ${{ ... }}`, etc., typically
   resolved per-environment via the same `&&`/`||` pattern as `service-id`. This is
   the only part that grows with secret count, and it's pure boilerplate, not logic.
3. A **generic** bash loop iterates over whatever `SECRET_*` env vars happen to be
   set and substitutes matching tokens — `for VAR_NAME in $(compgen -v | grep
   '^SECRET_')`. This loop never changes regardless of whether the service has 4
   secrets or 100; adding a secret is exactly one new `env:` line.
4. A check for any remaining `%%SECRET:...%%` token after substitution fails the
   job loudly, rather than pushing a broken placeholder to Render as if it were a
   real value.
5. The resolved content is pushed to Render's Secret Files API (`PUT
   /v1/services/{id}/secret-files/{name}`) **immediately, in the same script, same
   step** — never exposed as a job output. This is the same masked-output-blanking
   hazard described above; resolving and using a secret-derived value must happen
   together in one place, never split across a job boundary.

**Why this isn't a shared composite action or reusable workflow:** any such
abstraction would still need a fixed, pre-declared `inputs:`/`secrets:` schema — the
same "how many secrets" ceiling this design exists to avoid, just moved to a
different file. The only genuinely shareable part (the substitution algorithm) is
already O(1) in service-specific lines needed to invoke it, so there's little to
gain and a real safety cost (another job/step boundary the resolved value would
need to cross) from trying to factor it out further.

**Runtime consumption is entirely up to each service's own `Dockerfile`** — for
Spring, `ENV SPRING_CONFIG_IMPORT=optional:file:/etc/secrets/<name>` (works for
both `.properties` and `.yaml`, Spring picks the loader from the extension); a
non-Spring stack would read the same fixed Render mount path
(`/etc/secrets/<name>`) with its own config loader. `deployment-workflows` doesn't
need to change either way.

---

## Naming & Versioning

- Reference this repo with `@main` during the pilot phase. Once multiple services
  depend on it, pin production-critical callers to a commit SHA or a released tag
  (see `CHANGELOG.md`) instead of a moving branch.
- All third-party actions used inside this repo are pinned to a full commit SHA.
