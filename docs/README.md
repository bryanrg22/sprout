# Documentation

| Read this | For |
|---|---|
| [`DEVELOPING.md`](DEVELOPING.md) | Building, running the tests and evaluations, CI |
| [`EVAL_REPORT.md`](EVAL_REPORT.md) | Every measurement and decision, in numbered sections that are never rewritten |
| [`GOALS.md`](GOALS.md) | What is planned, what is done |
| [`RELEASING.md`](RELEASING.md) | How a merge becomes a TestFlight build |
| [`testflight.md`](testflight.md) | The one-time Apple account setup (signing, capabilities, CloudKit) |
| [`google-health-setup.md`](google-health-setup.md) | Connecting Fitbit through the Google Health API |
| [`../server/README.md`](../server/README.md) | The AI gateway: how a call is checked, deploying it |
| [`../SproutTests/LEDGER.md`](../SproutTests/LEDGER.md) | What each test file proves, and what it does not |

## Feature specifications

| Spec | Feature |
|---|---|
| [`adaptive-plan.md`](adaptive-plan.md) | The plan Vita builds and reviews |
| [`avatar-generation.md`](avatar-generation.md) | The character made from a photo |
| [`buddy-identity.md`](buddy-identity.md), [`buddy-sync.md`](buddy-sync.md) | Pairing two people and syncing their days through CloudKit |
| [`chat-standards.md`](chat-standards.md) | The chat: paging, errors, selection, accessibility |
| [`nutrition-detail.md`](nutrition-detail.md) | Nutrients beyond calories, and "unknown is never zero" |
| [`workout-redesign.md`](workout-redesign.md) | The Workouts tab |

## Records

| Folder | Holds |
|---|---|
| [`audits/`](audits/) | Dated audits of the whole app; findings are tracked in EVAL_REPORT |
| [`cloudkit/`](cloudkit/) | The CloudKit schema as deployed, and the model manifest CI checks it against |
| [`test-evidence/`](test-evidence/) | Test results captured for a release (`tooling/evidence/capture.sh`) |
| [`screenshots/`](screenshots/) | Screenshots used by the README and the specs |
| [`diagrams/`](diagrams/) | Diagrams used by the README |

Records written before 2026-11-24 (the audits, test evidence, `Evals/runs/` and the earlier
EVAL_REPORT sections) use the source folders' old names, `Victoria/`, `VictoriaTests/` and so
on; they are now `Sprout/`, `SproutTests/`. Records are not rewritten.
