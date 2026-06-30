# prompts/

Copy-paste prompts that let non-technical vendors run the Vendor Bridge pipeline
in [Claude Cowork](https://cowork.claude.ai) without installing or running the app.

Each prompt encodes the same logic the app applies — the source adapter
(`lib/adapters/`), the row filters and image transforms (`lib/transforms/`), and
the reconciliation context the app builds from `config/rosetta_stone.yaml` (see
`lib/adapters/context_builder.rb`).

| Prompt | Source | Does |
|---|---|---|
| `iheartjane.md` | iHeartJane product template (.xlsx) | Flatten to a clean CSV, then (optionally) reconcile against a POSaBIT catalog CSV |

## Keeping prompts in sync

These prompts duplicate logic that lives in code. When you change an adapter,
a row filter, or the mappings in `config/rosetta_stone.yaml`, update the matching
prompt here so vendors get the same result as the app.
