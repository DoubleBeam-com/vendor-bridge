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

lib/adapters/
  base.rb                       Abstract adapter interface (see Adapter Interface below)
  registry.rb                   In-memory adapter registry (register/fetch/available)
  iheartjane_v1.rb              iHeartJane XLSX parser — registered as "iheartjane"
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

## Adapter Interface

Every source system (iHeartJane, Dutchie, Leafly, etc.) gets its own adapter in `lib/adapters/`. An adapter extends `VendorBridge::Adapters::Base` and implements:

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

### `source_label → String`

Human-readable name for UI and error messages. Example: `"iHeartJane"`

### `category_mapping → Hash`

Maps vendor product categories to POSaBIT `product_type_name` values:

```ruby
{
  "Flower"      => "Flower",
  "Edible"      => "Edible Solid, Edible Liquid",
  "Vape"        => "Cartridge",
  "Concentrate" => "Concentrate, BHO",
  ...
}
```

### `field_mapping → Array<Hash>`

Maps vendor columns to POSaBIT columns. Used by the context builder to generate the field guide:

```ruby
[
  { vendor: "Brand",    posabit: "brand_name",  notes: "Also used for matching" },
  { vendor: "Strain",   posabit: "strain_name", notes: "Also used for matching" },
  { vendor: "Amount [g]", posabit: "weight",    notes: "Check Total Weight too" },
  ...
]
```

### Registration

At the bottom of each adapter file:

```ruby
Registry.register("iheartjane", IheartjaneV1)
```

Adapters are auto-loaded via glob — drop a new file in `lib/adapters/` and it's available immediately.

## Context File Format

The context builder (`lib/adapters/context_builder.rb`) generates a Markdown file designed to be loaded into any LLM. It contains:

1. **Role prompt** — "You are a product data reconciliation assistant"
2. **Matching rules** — Search by category → brand (fuzzy) → strain (fuzzy) → weight
3. **Category mapping** — Vendor categories → POSaBIT product types (from adapter)
4. **Field mapping** — Vendor columns → POSaBIT columns (from adapter)
5. **Output format** — Exact POSaBIT CSV columns in exact order
6. **UPDATE vs NEW rules**:
   - Match found → UPDATE: keep `id` and all `_id` fields from catalog
   - No match → NEW: leave `id` blank, leave `_id` fields blank
7. **Full POSaBIT catalog** — Embedded as CSV (typically ~900 rows, fits in context)
8. **Vendor data summary** — Column list, brand list, category list

The context file is source-agnostic — all source-specific details come from the adapter's `category_mapping` and `field_mapping`.

## Web App Flow (app.rb)

1. `GET /` — Renders upload form. Source dropdown populated from `Registry.available`.
2. `POST /upload` — Saves file, runs `adapter.flatten()`, stores result as pipeline JSON in `tmp/sessions/`.
3. `GET /preview/:id` — Shows stats cards. If POSaBIT catalog is loaded, shows context download button.
4. `GET /export/:id` — Downloads flattened CSV.
5. `POST /upload-posabit/:id` — Parses uploaded POSaBIT CSV, stores in pipeline, redirects to preview.
6. `GET /context/:id` — Generates and downloads the reconciliation .md file.

Pipeline state is stored as JSON files in `tmp/sessions/`. Each session has a unique hex ID.

## Adding a New Source

1. Create `lib/adapters/newsource_v1.rb`:

```ruby
require "csv"  # or whatever parser you need
require_relative "base"
require_relative "registry"

module VendorBridge
  module Adapters
    class NewSourceV1 < Base
      def source_label
        "New Source"
      end

      def category_mapping
        {
          "Flower" => "Flower",
          # ... map vendor categories to POSaBIT product types
        }
      end

      def field_mapping
        [
          { vendor: "product_name", posabit: "name", notes: "" },
          { vendor: "brand",        posabit: "brand_name", notes: "Used for matching" },
          # ...
        ]
      end

      def flatten(file_path)
        # Parse the file, filter junk rows, return { rows:, columns:, stats: }
      end
    end

    Registry.register("newsource", NewSourceV1)
  end
end
```

2. That's it. The glob loader picks it up. The web UI shows it in the dropdown. The context builder uses its mappings.

## Known Debt

- **RowFilter is iHeartJane-specific**: `lib/transforms/row_filter.rb` has hardcoded column names like `"Strain"`, `"Brand"`, `"Product Name (Internal Use)"`. New sources with different column names need their own filter logic. Should be moved into each adapter.
- **Tests only cover iHeartJane**: `spec/app_spec.rb` uses iHeartJane fixtures. New sources need their own test files and sample data.
- **No automated matching**: The reconciliation step is manual (vendor pastes into LLM). Future: could run matching server-side.

## Tech Stack

- **Ruby 3.1+**, Sinatra, Puma
- **Roo** gem for Excel parsing
- **Tailwind CSS** (CDN) for the web UI
- No database — pipeline state is JSON files in `tmp/`
- No JavaScript framework — vanilla JS for drag-and-drop only
