# Template Guide: Onboarding a New Service

This guide shows how to wire a new Java/Spring Boot service into the CI/CD templates
defined in this repository. Service repos stay thin — they call these reusable
workflows instead of duplicating build/test/deploy logic.

Reference implementation: `data-ingestion` + `data-ingestion-cd`.

---

## 1. Prerequisites

- The service repo has a Maven project (`pom.xml`, `mvnw`) with JUnit tests and the
  JaCoCo plugin bound to the `verify` phase (see [Coverage Threshold Convention](#coverage-threshold-convention)).
- A `Dockerfile` exists in the service repo (multi-stage Maven build recommended).
- A SonarQube Cloud project exists for the service (see Phase 0 setup). SonarQube
  Cloud **requires** `sonar.organization` — pass `sonar-organization` in `pr.yml`
  and `main.yml` (see below) or analysis fails with
  `You must define the following mandatory properties for '<key>': sonar.organization`.
- A dedicated `<service-name>-cd` repository exists (see step 4).
- The `city-pulse-automation` GitHub App is installed on both the application repo
  and its `-cd` repo.
- Repo secrets `SONAR_TOKEN` and `AUTOMATION_APP_PRIVATE_KEY` are configured on the
  application repo, plus the repo **variable** (not secret — the `secrets` context
  isn't readable inside a reusable-workflow call's `with:` block, only inside its
  `secrets:` block, and the App ID isn't sensitive data anyway) `AUTOMATION_APP_ID`.
  `RENDER_API_KEY` is configured on the `-cd` repo.

---

## 2. Application repo: three thin workflows

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
    uses: mustapha-smail-org/deployment-workflows/.github/workflows/ci-pr.yml@main
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
    uses: mustapha-smail-org/deployment-workflows/.github/workflows/ci-main.yml@main
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
      packages: read
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
`WORKFLOW_CONTRACTS.md` for what each one requires.

---

## 3. Coverage Threshold Convention

`ci-pr.yml` and `ci-main.yml` pass `-Djacoco.line.coverage.minimum=<ratio>` to
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

---

## 5. CODEOWNERS

Protect the production file so promotions require review:

```
/environments/production.yaml @mustapha-smail-org/data-platform-team
```

---

## 6. What NOT to duplicate

Do not copy Maven, Sonar, or Docker steps into a service repo's own workflow files.
If a service needs a step the templates don't support, extend the composite action or
reusable workflow in this repo instead — see `WORKFLOW_CONTRACTS.md` for the current
inputs/outputs, and open a PR here so every service benefits.

---

## 7. Adding a new deployment provider

See `docs/ADDING_NEW_PROVIDER.md` (or the `deploy-render.yml` workflow as a
reference) for the adapter contract: same inputs/outputs shape, different
implementation.
