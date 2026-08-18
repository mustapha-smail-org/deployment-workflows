# Template Guide: Onboarding a New Service

This guide shows how to wire a new service into the CI/CD templates defined in this
repository. Service repos stay thin — they call these reusable workflows instead of
duplicating build/test/deploy logic.

Two stacks are supported today:

- **Java/Spring Boot** — Maven build, JaCoCo coverage, `ci-pr-java.yml` / `ci-main-java.yml`.
  Reference implementation: `data-ingestion` + `data-ingestion-cd`.
- **Node/Vite (SPA)** — npm build, Vitest coverage, `ci-pr-node.yml` /
  `ci-main-node.yml`. Reference implementation: `frontend` + `frontend-cd`.

`ci-release.yml` and `deploy-render.yml` are shared by both stacks unchanged — they
operate purely on an already-built OCI image and its digest, with no
language-specific logic. Skip straight to [§4](#4-service-cd-repo-desired-state--thin-deploy-workflow)
for those regardless of stack.

---

## 1a. Prerequisites (Java/Spring)

- The service repo has a Maven project (`pom.xml`, `mvnw`) with JUnit tests and the
  JaCoCo plugin bound to the `verify` phase (see [§3a](#3a-coverage-threshold-convention-java)).
- A `Dockerfile` exists in the service repo (multi-stage Maven build recommended).
- A SonarQube Cloud project exists for the service (see Phase 0 setup). SonarQube
  Cloud **requires** `sonar.organization` — pass `sonar-organization` in `pr.yml`
  and `main.yml` (see below) or analysis fails with
  `You must define the following mandatory properties for '<key>': sonar.organization`.
- A dedicated `<service-name>-cd` repository exists (see [§4](#4-service-cd-repo-desired-state--thin-deploy-workflow)).
- The `city-pulse-automation` GitHub App is installed on both the application repo
  and its `-cd` repo.
- Repo secrets `SONAR_TOKEN` and `AUTOMATION_APP_PRIVATE_KEY` are configured on the
  application repo, plus the repo **variable** (not secret — the `secrets` context
  isn't readable inside a reusable-workflow call's `with:` block, only inside its
  `secrets:` block, and the App ID isn't sensitive data anyway) `AUTOMATION_APP_ID`.
  `RENDER_API_KEY` is configured on the `-cd` repo.

## 1b. Prerequisites (Node/Vite SPA)

- The service repo has a Node project (`package.json`, `package-lock.json` — the
  actions cache and resolve versions off the lockfile, so it must be committed) with
  `lint`, `format:check`, `typecheck`, `test:coverage`, and `build` npm scripts.
  `test:coverage` must emit both `coverage/coverage-summary.json` (consumed by
  `node-verify`'s threshold check) and `coverage/lcov.info` (consumed by
  `sonar-analysis-node`) — for Vitest, add `'json-summary'` and `'lcov'` to
  `coverage.reporter` in `vitest.config.ts`.
- A `Dockerfile` exists that builds the app and serves the static output (nginx is
  the reference setup — see the "Runtime configuration" note below for why the
  build can't simply bake `VITE_*` env vars in like a typical Vite deploy).
- A `sonar-project.properties` exists in the repo root (or `working-directory`) with
  `sonar.sources`, `sonar.tests`, `sonar.exclusions`, and
  `sonar.javascript.lcov.reportPaths=coverage/lcov.info`. Unlike the Java action,
  `sonar-analysis-node` does not pass structural config as CLI flags — see
  `WORKFLOW_CONTRACTS.md`.
- A SonarQube Cloud project exists for the service; same `sonar-organization`
  requirement as the Java stack.
- If the app uses Playwright for e2e, `playwright.config.ts`'s `webServer` should
  build and serve a production bundle itself (see `frontend/playwright.config.ts`)
  so `node-e2e` needs no separate build step.
- Same `-cd` repo, GitHub App, and secrets/variable prerequisites as [§1a](#1a-prerequisites-javaspring).

**Runtime configuration, not build-time `VITE_*` baking:** the central principle of
this repo is "build once, promote the same immutable artifact through every
environment" ([§ Design principles](../README.md#design-principles)). Vite's normal
`VITE_*` env var mechanism bakes values into the JS bundle at build time, which would
mean building a separate image per environment — breaking that principle and
`ci-release.yml`'s no-rebuild promotion. Instead, keep build-time `VITE_*` vars as
**dev-only fallbacks** (see `.env.example`), and have the container's entrypoint
write a small `config.js` (`window.__APP_CONFIG__ = {...}`) into the served
directory from a file mounted at deploy time, before nginx starts. The app's config
module should merge `window.__APP_CONFIG__` over `import.meta.env` at runtime. This
is a service-specific pattern (Dockerfile + entrypoint script), not something
`node-verify`/`ci-main-node.yml` need to know about — see [§4](#4-service-cd-repo-desired-state--thin-deploy-workflow)'s
"Optional: externalized config file" for how the value gets to the container.

---

## 2a. Application repo: three thin workflows (Java)

Create these three files in `<service>/.github/workflows/`. Nothing else is needed —
no Maven config duplication, no Docker build logic, no Sonar setup beyond the project
key.

### `pr.yml`

```yaml
name: PR
on:
  pull_request:
    branches: [main]

jobs:
  ci:
    permissions:
      contents: read
    uses: mustapha-smail-org/deployment-workflows/.github/workflows/ci-pr-java.yml@main
    with:
      java-version: '21'
      sonar-project-key: <service-name>
      sonar-project-name: 'CityPulse <Service Name>'
      sonar-organization: mustapha-smail-org
      jacoco-threshold: '70'
    secrets:
      sonar-token: ${{ secrets.SONAR_TOKEN }}
```

### `main.yml`

```yaml
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
    uses: mustapha-smail-org/deployment-workflows/.github/workflows/ci-main-java.yml@main
    with:
      service-name: <service-name>
      java-version: '21'
      sonar-project-key: <service-name>
      sonar-project-name: 'CityPulse <Service Name>'
      sonar-organization: mustapha-smail-org
      jacoco-threshold: '70'
      automation-app-id: ${{ vars.AUTOMATION_APP_ID }}
    secrets:
      sonar-token: ${{ secrets.SONAR_TOKEN }}
      automation-app-private-key: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
```

### `release.yml`

```yaml
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
    uses: mustapha-smail-org/deployment-workflows/.github/workflows/ci-release.yml@main
    with:
      service-name: <service-name>
      automation-app-id: ${{ vars.AUTOMATION_APP_ID }}
    secrets:
      automation-app-private-key: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
```

By default, `service-cd-repository` resolves to `<owner>/<service-name>-cd`. Pass it
explicitly only if the CD repo name doesn't follow that convention.

**Permissions gotcha:** a reusable workflow can never receive more permissions than
its caller job explicitly grants — GitHub Actions rejects the run at parse time
(`... is only allowed 'packages: read, id-token: none'`) if the caller relies on the
default token permissions instead of declaring its own `permissions:` block. Each
`with:`/`uses:` job above must declare a `permissions:` block that matches (or
exceeds) the `permissions:` the target reusable workflow itself declares — see
`WORKFLOW_CONTRACTS.md` for what each one requires. This applies identically to the
Node workflows in [§2b](#2b-application-repo-three-thin-workflows-nodevite-spa).

**`release.yml` needs `packages: write`, not `read`:** counterintuitively, even
though the release flow never rebuilds or uploads new image layers, `crane tag`
still performs a manifest `PUT` to attach the new semver tag to the existing
digest — and GHCR requires write/push permission for any operation that creates
or moves a tag, regardless of whether new blob content is involved. `packages:
read` here fails at runtime (not parse time) with
`DENIED: installation not allowed to Write organization package`. `release.yml` is
shared by both stacks, so this applies to Node callers too.

---

## 2b. Application repo: three thin workflows (Node/Vite SPA)

Create these three files in `<service>/.github/workflows/`. Nothing else is needed —
no npm script duplication, no Docker build logic, no Sonar setup beyond the project
key.

### `pr.yml`

```yaml
name: PR
on:
  pull_request:
    branches: [main]

jobs:
  ci:
    permissions:
      contents: read
    uses: mustapha-smail-org/deployment-workflows/.github/workflows/ci-pr-node.yml@main
    with:
      node-version: '22'
      sonar-project-key: <service-name>
      sonar-project-name: 'CityPulse <Service Name>'
      sonar-organization: mustapha-smail-org
      coverage-threshold: '70'
    secrets:
      sonar-token: ${{ secrets.SONAR_TOKEN }}
```

`run-e2e` defaults to `true` here — a PR is exactly where the Playwright suite
should gate the merge. Set it to `false` (or tune `e2e-browsers`) if a given
service's suite isn't ready yet.

### `main.yml`

```yaml
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
    uses: mustapha-smail-org/deployment-workflows/.github/workflows/ci-main-node.yml@main
    with:
      service-name: <service-name>
      node-version: '22'
      sonar-project-key: <service-name>
      sonar-project-name: 'CityPulse <Service Name>'
      sonar-organization: mustapha-smail-org
      coverage-threshold: '70'
      automation-app-id: ${{ vars.AUTOMATION_APP_ID }}
    secrets:
      sonar-token: ${{ secrets.SONAR_TOKEN }}
      automation-app-private-key: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
```

`run-e2e` defaults to `false` here, unlike `pr.yml` — the e2e suite already gated
this commit on the PR, so re-running it on `main` would only add latency to the path
to a dev deploy without new information. Flip it on for a given service if you want
e2e as a second, post-merge safety net.

### `release.yml`

Identical in shape to the Java version — `ci-release.yml` is stack-agnostic:

```yaml
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
    uses: mustapha-smail-org/deployment-workflows/.github/workflows/ci-release.yml@main
    with:
      service-name: <service-name>
      automation-app-id: ${{ vars.AUTOMATION_APP_ID }}
    secrets:
      automation-app-private-key: ${{ secrets.AUTOMATION_APP_PRIVATE_KEY }}
```

**`sonar-analysis-node` must run in the same job as `node-verify`, after it:** it
reads `coverage/lcov.info` off the runner's disk, so splitting them across jobs
(which run on separate runners with no shared filesystem) breaks the gate silently
— Sonar would just report 0% coverage rather than erroring. `ci-pr-node.yml` and
`ci-main-node.yml` already do this correctly; if you extend either workflow, keep
the two steps together.

---

## 3a. Coverage Threshold Convention (Java)

`ci-pr-java.yml` and `ci-main-java.yml` pass `-Djacoco.line.coverage.minimum=<ratio>` to
`mvnw verify` (ratio = `jacoco-threshold / 100`). Your service's `pom.xml` must define
a JaCoCo `check` execution bound to `verify` that reads this property:

```xml
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <executions>
    <execution>
      <goals><goal>prepare-agent</goal></goals>
    </execution>
    <execution>
      <id>report</id>
      <phase>prepare-package</phase>
      <goals><goal>report</goal></goals>
    </execution>
    <execution>
      <id>coverage-check</id>
      <phase>verify</phase>
      <goals><goal>check</goal></goals>
      <configuration>
        <rules>
          <rule>
            <element>BUNDLE</element>
            <limits>
              <limit>
                <counter>LINE</counter>
                <value>COVEREDRATIO</value>
                <minimum>${jacoco.line.coverage.minimum}</minimum>
              </limit>
            </limits>
          </rule>
        </rules>
      </configuration>
    </execution>
  </executions>
</plugin>
```

Define a default so local `mvn verify` still works without the CI flag:

```xml
<properties>
  <jacoco.line.coverage.minimum>0.70</jacoco.line.coverage.minimum>
</properties>
```

## 3b. Coverage Threshold Convention (Node)

Unlike the Java action, `node-verify` does **not** pass the threshold into the test
runner's own config — it runs your `test-command` as-is (default `npm run
test:coverage`) and then enforces `coverage-threshold` itself by reading
`coverage/coverage-summary.json` after the run and failing the step if
`total.lines.pct` is below it. This keeps `vitest.config.ts` threshold-free, so a
local `npm run test:coverage` behaves identically to CI regardless of which
service's `coverage-threshold` value is passed in.

Your `vitest.config.ts` (or equivalent) only needs to emit the right reporters:

```ts
coverage: {
  provider: 'v8',
  reporter: ['text', 'html', 'lcov', 'json-summary'],
  // ...
}
```

`lcov` feeds `sonar-analysis-node`; `json-summary` feeds `node-verify`'s own
threshold check. Pick a real threshold based on the service's actual coverage
rather than reusing the `70` default unmodified — a threshold below current
coverage protects nothing.

---

## 4. Service CD repo: desired state + thin deploy workflow

Create `<service-name>-cd` with:

```
service.yaml
environments/
  dev.yaml
  staging.yaml
  production.yaml
CODEOWNERS
.github/workflows/deploy.yml
README.md
```

`service.yaml` and each `environments/*.yaml` must conform to
`contracts/service-schema.json` and `contracts/environment-schema.json` respectively.
This layer is identical for Java and Node services — it only ever talks about an
image repository, a digest, and a Render service ID, none of which are
stack-specific.

`deploy.yml` is a thin wrapper: it obtains a `city-pulse-automation` App token,
checks out using that token, updates the target environment file with the new
digest/tag, commits and pushes, then calls `deploy-render.yml`. See
`data-ingestion-cd/.github/workflows/deploy.yml` for the reference implementation.

**The `-cd` repo needs its own copy of the App credentials** — `AUTOMATION_APP_ID`
(variable) and `AUTOMATION_APP_PRIVATE_KEY` (secret), same values as the
application repo. Secrets/variables don't cross repos, and the App must actually be
the one pushing (not the default `GITHUB_TOKEN`) for its bypass-list entry on the
`main` ruleset to apply — a push authenticated as `github-actions[bot]` is a
different actor and gets rejected with `GH013` even if the App is on the bypass
list.

**Render service IDs are secrets, not desired-state config:** a real Render
`srv-...` ID is effectively an access handle, so it does not belong in
`environments/*.yaml`. Store `RENDER_SERVICE_ID_DEV`, `RENDER_SERVICE_ID_STAGING`,
and `RENDER_SERVICE_ID_PRODUCTION` as repo secrets on the `-cd` repo instead, and
have `deploy.yml`'s `deploy` job resolve the right one per environment **directly
in its `secrets:` block**, via a plain `&&`/`||` expression on `inputs.environment`
(see `data-ingestion-cd/.github/workflows/deploy.yml`). Do **not** resolve it in a
`run:` step and expose it as a job output instead — GitHub Actions silently blanks
any job output derived from a masked value once it's passed into another job's
`with:`/`secrets:` block, which fails with a confusing downstream
`service-id is required` error and no indication of the real cause. See
`WORKFLOW_CONTRACTS.md`, "Secret job outputs get blanked, not passed through."

**Render free-plan note:** if you only have two Render services available, give
`RENDER_SERVICE_ID_DEV` and `RENDER_SERVICE_ID_STAGING` the same value. Nothing
else changes — upgrade later by pointing `RENDER_SERVICE_ID_STAGING` at a real
third service.

**Optional: externalized config file.** A service can mount a file onto Render at
a fixed, language-agnostic path (`/etc/secrets/<name>`) before its image deploys.
Skip this whole section if a service doesn't need it.

This is **entirely a service-specific pattern, implemented in that service's own
`-cd` repo — not a `deploy-render.yml` capability.** The reasoning: the number and
names of secrets a service needs is unbounded (4 today, 100 for the next service),
and GitHub Actions requires every secret a script touches to be named explicitly
at authoring time — there's no way to look up `secrets.<name>` dynamically from a
name discovered at runtime. Baking any fixed "how many secrets" ceiling into the
*shared* `deploy-render.yml` doesn't scale; each service enumerating its own,
however many, does.

See `WORKFLOW_CONTRACTS.md`'s "Externalized App Config" section for the full
pattern and why it's structured this way, and
`data-ingestion-cd/config/*.yaml` + its `deploy.yml`'s `push-config` job for the
reference implementation: a tracked YAML file per environment where secret values
are `%%SECRET:NAME%%` tokens rather than real values, resolved by a generic bash
loop (unchanged regardless of secret count — only the `env:` block declaring each
secret grows) and pushed to Render directly, in the same script, before the actual
image deploy. Each service's own `Dockerfile` decides how its runtime consumes the
mounted file — for Spring, one `ENV SPRING_CONFIG_IMPORT=optional:
file:/etc/secrets/<name>` line (works for both `.properties` and `.yaml`, Spring
picks the loader from the extension); a non-Spring stack would read the same
fixed path with its own config loader.

**For a Node/Vite SPA specifically**, this same mechanism is how runtime
configuration (see [§1b](#1b-prerequisites-nodevite-spa)) reaches the container: the
per-environment JSON/YAML file becomes the source for the container entrypoint's
`window.__APP_CONFIG__` script, pushed to a Render secret file the entrypoint reads
at startup — not consumed by Spring's `SPRING_CONFIG_IMPORT`, but the same
`%%SECRET:NAME%%`-token-and-substitution pattern applies unchanged.

---

## 5. CODEOWNERS

Protect the production file so promotions require review:

```
/environments/production.yaml @mustapha-smail-org/data-platform-team
```

---

## 6. What NOT to duplicate

Do not copy Maven/npm, Sonar, or Docker steps into a service repo's own workflow
files. If a service needs a step the templates don't support, extend the composite
action or reusable workflow in this repo instead — see `WORKFLOW_CONTRACTS.md` for
the current inputs/outputs, and open a PR here so every service benefits.

---

## 7. Adding a new deployment provider

See `docs/ADDING_NEW_PROVIDER.md` (or the `deploy-render.yml` workflow as a
reference) for the adapter contract: same inputs/outputs shape, different
implementation. Stack-agnostic — a new provider adapter serves Java and Node
callers identically.
