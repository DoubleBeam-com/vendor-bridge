# Vendor Bridge

Vendor Bridge converts messy vendor product exports (XLSX) into clean CSV files ready for POSaBIT import, and generates AI-ready context files for reconciling vendor data against an existing POSaBIT catalog.

## Quick Start for Reconciliation

When a user asks you to reconcile, match, or merge product data:

1. **Read the context file first**: `data_files/reconciliation_context.md` — this is the single source of truth for the current reconciliation job. It contains the matching rules, field mappings, category mappings, output format, and workflow.
2. **Load the data files** from `data_files/`:
   - `posabit_data.csv` — the existing POSaBIT catalog (your base; every row stays)
   - `iheartjane_flattened.csv` — incoming vendor products (or whichever `*_flattened.csv` exists)
3. **Follow the instructions** in `reconciliation_context.md` exactly. It tells you how to match, what to update, and what format to output.
4. **Write outputs** to `data_files/`:
   - `reconciliation_output.csv` — the import-ready file
   - `reconciliation_summary.md` — human-readable summary of changes

## Project Structure

```
app.rb                           Sinatra web app (upload, flatten, preview, context generation)
config.ru                        Rack config
flatten.rb                       CLI alternative: ruby flatten.rb [--source NAME] INPUT_FILE

config/rosetta_stone.yaml        Single source of truth for all field & category mappings

lib/adapters/
  registry.rb                    Loads rosetta_stone.yaml, provides source configs
  iheartjane_v1.rb               iHeartJane XLSX parser (multi-sheet flattening)
  context_builder.rb             Generates the reconciliation_context.md file

lib/transforms/
  row_filter.rb                  Filters junk rows (examples, headers, empties)

views/                           ERB templates (Tailwind CSS via CDN)
spec/                            RSpec tests
samples/                         Test fixtures (gitignored)
data_files/                      Working data directory (gitignored)
```

## Tech Stack

Ruby 3.1+, Sinatra 4, Puma, Roo (Excel parsing), RSpec. No database — pipeline state is JSON in `tmp/`. Tailwind CSS via CDN, no JS framework.

## Running

```bash
bundle install
bundle exec puma config.ru -p 4567     # web UI at http://localhost:4567
bundle exec rspec                       # tests
```

## Key Concepts

- **Rosetta Stone** (`config/rosetta_stone.yaml`): All vendor-to-POSaBIT mappings live here. Category mappings, field mappings, and per-category matching hints. Adapters don't contain mapping logic.
- **Adapters**: Parse source files and return `{ rows:, columns:, stats: }`. Registered via `Registry.register_adapter`.
- **Context Builder**: Generates the markdown reconciliation instructions from pipeline state + rosetta stone config. Source-agnostic.
- **Pipeline**: Upload → Flatten → Preview → (optional) Upload POSaBIT CSV → Generate Context → AI Reconciliation.

## Known Debt

- `RowFilter` has hardcoded iHeartJane column names — needs to be adapter-configurable for new sources.
- Tests only cover iHeartJane; new sources need their own fixtures.
- Reconciliation is manual (AI-driven via context file); no server-side matching yet.
