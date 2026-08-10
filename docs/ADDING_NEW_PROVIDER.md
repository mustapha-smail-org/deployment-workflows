# Adding a New Deployment Provider

`deploy-render.yml` is the reference adapter. A new provider (Kubernetes, AWS ECS,
etc.) is a new `deploy-<provider>.yml` reusable workflow implementing the same
contract shape, not a fork of service-specific logic.

## Required contract

Every adapter workflow MUST:

1. Accept `workflow_call` inputs: `service-name`, `environment`,
   `image-repository`, `image-digest`, plus whatever provider-specific identifier
   is needed (Render: `service-id`; Kubernetes: `cluster`/`namespace`; ECS:
   `cluster`/`service`/`region`).
2. Accept `health-check-url` / `health-check-path` (optional, but implement the
   check when provided).
3. Validate `image-digest` matches `^sha256:[a-f0-9]{64}$` before doing anything
   provider-specific — never deploy a mutable tag.
4. Emit outputs: `deployment-status` (`success`/`failed`), `deployment-id`,
   `deployment-url`.
5. Define a concurrency group `deploy-<service-name>-<environment>`, cancelling
   in-progress runs only for `dev`.
6. Fail loudly (non-zero exit, `::error::` annotation) rather than leaving the
   job green on partial failure.
7. Use short-lived/OIDC credentials where the provider supports it. Only fall back
   to a static API key (as Render currently requires) when no better option exists.
8. Never modify the application repository — adapters only read the inputs passed
   to them and talk to the target platform.

## Steps to add one

1. Copy `deploy-render.yml` as a starting skeleton.
2. Replace the "Trigger deployment" / "Wait for stable state" / "Health check"
   steps with the provider's actual API/CLI calls.
3. Add the new provider to `contracts/service-schema.json`
   (`spec.provider.enum`).
4. Document the new workflow's inputs/outputs in `WORKFLOW_CONTRACTS.md`.
5. Update a service CD repo's `deploy.yml` to call the new workflow — application
   repos and their `ci-*.yml` callers do not need to change.
