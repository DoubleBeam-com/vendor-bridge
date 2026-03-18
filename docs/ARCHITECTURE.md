# Vendor Bridge — Architecture Reference

> Load this file into any AI assistant for full project context.

## What This Project Does

Vendor Bridge converts messy vendor product exports into clean CSV files ready for POSaBIT import. It also generates AI-ready context files that let vendors use Claude, ChatGPT, or any LLM to reconcile vendor data against their existing POSaBIT catalog.

## Pipeline Flow

```
1. Vendor uploads product export (XLSX)
        ↓
2. Adapter flattens it → clean CSV (one row per product, all sheets combined)
        ↓
3. Preview page shows stats (products per category)
        ↓
4. Vendor downloads flattened CSV
        ↓
5. Vendor uploads their current POSaBIT catalog (CSV export)
        ↓
6. Context builder generates a reconciliation .md file
        ↓
7. Vendor loads .md into an LLM, pastes vendor rows
        ↓
8. LLM outputs ingest-ready CSV:
   - id filled → UPDATE (existing product)
   - id blank  → NEW (create in POSaBIT)
```

## File Map

```
app.rb                          Sinatra web server
                                Routes: GET /
                                        POST /upload
                                        GET /preview/:id
                                        GET /export/:id
                                        POST /upload-posabit/:id
                                        GET /context/:id

config.ru                       Rack config (loads app.rb)

flatten.rb                      CLI alternative to the web UI
                                Usage: ruby flatten.rb [--source NAME] [--output PATH] INPUT_FILE

config/
  rosetta_stone.yaml            Single source of truth for all field & category mappings
                                Two sections: sources (per-source metadata) and
                                field_mappings (POSaBIT field → vendor column dictionary)

lib/adapters/
  registry.rb                   Loads rosetta_stone.yaml, provides fetch/adapter_for/available
  iheartjane_v1.rb              iHeartJane XLSX parser (flatten only, no mapping config)
  context_builder.rb            Generates the LLM reconciliation .md file

lib/transforms/
  row_filter.rb                 Filters junk rows (examples, section headers, empties)
                                ⚠ Currently hardcoded to iHeartJane column names

views/
  layout.erb                    Base HTML — Tailwind CSS (CDN), POSaBIT green branding
  index.erb                     Upload form with drag-and-drop, source dropdown
  preview.erb                   Stats cards + flattened CSV download + POSaBIT upload + context download
  error.erb                     Friendly error page (no backtraces shown to vendors)

public/                         Static assets (currently empty, Tailwind loaded via CDN)
spec/                           RSpec tests
samples/                        Test fixtures (gitignored — contains vendor data)
```

## Rosetta Stone (`config/rosetta_stone.yaml`)

All field and category mappings live in a single YAML file. It has two sections:

### `sources` — per-source metadata

Each source (iheartjane, cultivera, etc.) defines:
- `label` — human-readable name for UI and error messages
- `adapter` — which Ruby flatten class to instantiate (e.g. `iheartjane_v1`)
- `category_mapping` — maps vendor product categories to POSaBIT `product_type_name` values

### `field_mappings` — the dictionary

Keyed by **POSaBIT field name**. Each entry lists the vendor column name per source:

```yaml
field_mappings:
  brand_name:
    iheartjane: Brand
    cultivera: brand
    notes: Also used for matching

  strain_name:
    iheartjane: Strain
    cultivera: strain_name
    notes: Also used for matching
```

The registry reads this file and derives the per-source `[{vendor, posabit, notes}]` array that the context builder renders into the reconciliation file.

## Adapter Interface

Adapters are standalone Ruby classes in `lib/adapters/`. They have one job: parse a source file and return flat product data. All mapping config lives in `rosetta_stone.yaml`, not in the adapter.

### `flatten(file_path) → Hash`

Parse the source file and return:

```ruby
{
  rows: [                           # Array of hashes, one per product
    {
      "Brand" => "Phat Panda",
      "Strain" => "Blue Dream",
      "_source_sheet" => "Flower",  # Synthetic: which sheet/tab it came from
      "_product_category" => "Flower", # Synthetic: normalized category
      "_source_row" => 5,           # Synthetic: original row number
      ...                           # All other columns from the source
    },
    ...
  ],
  columns: [                        # Ordered list of all column names
    "_source_sheet", "_product_category", "_source_row",
    "Brand", "Strain", ...
  ],
  stats: {                          # Per-sheet/category counts
    "Flower" => { total: 100, kept: 80 },
    "Edible" => { total: 50, kept: 45 },
    ...
  }
}
```

### Registration

At the bottom of each adapter file, register the class with its key from `rosetta_stone.yaml`:

```ruby
Registry.register_adapter("iheartjane_v1", IheartjaneV1)
```

Adapter files are auto-loaded via glob in `app.rb`. The registry matches the `adapter` key from the YAML to the registered class.

## Context File Format

The context builder (`lib/adapters/context_builder.rb`) generates a Markdown file designed to be loaded into any LLM. It contains:

1. **File references** — Points the LLM to the data files it needs
2. **Matching rules** — Search by category → brand (fuzzy) → strain (fuzzy) → weight
3. **Category mapping** — Vendor categories → POSaBIT product types (from rosetta stone)
4. **Field mapping** — Vendor columns → POSaBIT columns (derived from rosetta stone)
5. **ID resolution** — Instructions to build lookup tables from the catalog and populate `_id` fields by fuzzy-matching `_name` fields
6. **Output format** — Exact POSaBIT CSV columns in exact order
7. **UPDATE vs NEW rules**:
   - Match found → UPDATE: keep `id` and all `_id` fields from catalog
   - No match → NEW: leave `id` blank, resolve `_id` fields from lookup tables

The context file is source-agnostic — all source-specific details come from `rosetta_stone.yaml`.

## Web App Flow (app.rb)

1. `GET /` — Renders upload form. Source dropdown populated from `Registry.available`.
2. `POST /upload` — Saves file, loads source config from registry, runs `adapter.flatten()`, stores result as pipeline JSON in `tmp/sessions/`.
3. `GET /preview/:id` — Shows stats cards. If POSaBIT catalog is loaded, shows context download button.
4. `GET /export/:id` — Downloads flattened CSV.
5. `POST /upload-posabit/:id` — Parses uploaded POSaBIT CSV, stores in pipeline, auto-generates context file, redirects to preview.
6. `GET /context/:id` — Downloads the reconciliation .md file.

Pipeline state is stored as JSON files in `tmp/sessions/`. Each session has a unique hex ID.

## Adding a New Source

### 1. Add mappings to `config/rosetta_stone.yaml`

Under `sources`, add the new source with its label, adapter, and category mapping. Under `field_mappings`, add the vendor column name for each POSaBIT field:

```yaml
sources:
  cultivera:
    label: Cultivera
    adapter: generic_csv       # or a custom adapter if the file format needs special parsing
    category_mapping:
      flower: Flower
      edible: "Edible Solid, Edible Liquid"

field_mappings:
  brand_name:
    iheartjane: Brand
    cultivera: brand           # ← add a line per source
```

### 2. Create an adapter (only if the file format needs special parsing)

If the source uses a standard CSV, you may be able to reuse a generic adapter. If it needs custom parsing (e.g. multi-sheet XLSX like iHeartJane), create `lib/adapters/cultivera_v1.rb`:

```ruby
require_relative "registry"

module VendorBridge
  module Adapters
    class CultiveraV1
      def flatten(file_path)
        # Parse the file, filter junk rows, return { rows:, columns:, stats: }
      end
    end

    Registry.register_adapter("cultivera_v1", CultiveraV1)
  end
end
```

That's it. The glob loader picks it up. The web UI shows it in the dropdown. The context builder uses the rosetta stone mappings automatically.

## Known Debt

- **RowFilter is iHeartJane-specific**: `lib/transforms/row_filter.rb` has hardcoded column names like `"Strain"`, `"Brand"`, `"Product Name (Internal Use)"`. New sources with different column names need their own filter logic. Should be moved into each adapter or made configurable.
- **Tests only cover iHeartJane**: `spec/app_spec.rb` uses iHeartJane fixtures. New sources need their own test files and sample data.
- **No automated matching**: The reconciliation step is manual (vendor loads context into LLM). Future: could run matching server-side.

## Tech Stack

- **Ruby 3.1+**, Sinatra, Puma
- **Roo** gem for Excel parsing
- **Tailwind CSS** (CDN) for the web UI
- No database — pipeline state is JSON files in `tmp/`
- No JavaScript framework — vanilla JS for drag-and-drop only
