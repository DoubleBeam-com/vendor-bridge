module VendorBridge
  module Adapters
    class ContextBuilder
      def initialize(pipeline)
        @pipeline = pipeline
      end

      def generate(data_dir:)
        source         = @pipeline["source"]
        source_label   = @pipeline["source_label"] || source
        cat_mapping    = @pipeline["category_mapping"] || {}
        field_map      = @pipeline["field_mapping"] || []
        posabit_cols   = @pipeline["posabit_columns"] || []

        <<~MD
# POSaBIT Product Reconciliation

> Upload this file to [Claude Cowork](https://cowork.claude.ai) or any AI assistant.
> Then upload the two data files below and ask to reconcile them.

---

## Data Files

These files are in the `data_files/` folder:

1. **`#{source}_flattened.csv`** — Incoming vendor products (from #{source_label})
2. **`posabit_data.csv`** — Current POSaBIT catalog

Upload both files to the conversation along with this context file.

---

## Your Role

You are a product data reconciliation assistant. The user has uploaded two CSV files:

- The **vendor file** (`#{source}_flattened.csv`) contains new/updated products from #{source_label}.
- The **POSaBIT file** (`posabit_data.csv`) contains the store's current product catalog.

For each row in the vendor file, determine whether it matches an existing product in the POSaBIT catalog (UPDATE) or is brand new (NEW).

---

## Matching Rules

For each incoming vendor product, search the POSaBIT catalog using these fields **in order of priority**:

1. **Product category** — Match the vendor's `_product_category` to the catalog's `product_type_name`:
#{category_mapping_text(cat_mapping)}

2. **Brand name** — Fuzzy match the vendor's `Brand` against `brand_name`. Ignore case and minor differences (e.g., "phat panda" = "Phat Panda").

3. **Strain name** — Fuzzy match the vendor's `Strain` against `strain_name`. Handle minor spelling differences, abbreviations, and missing words.

4. **Weight / Pack Size** — If multiple catalog entries match on category + brand + strain, use weight or pack size to pick the right one.

### Decision

- **All 3 match** (+ weight if applicable) → **UPDATE**. Copy the matching catalog row. Keep `id` and all ID fields. Update only fields where the vendor has better/newer data.
- **Category + Brand match but strain differs** → Check if catalog `name` contains the vendor's product name or strain. If yes → UPDATE. If no → **NEW**.
- **No match on category + brand** → **NEW**. Leave `id` and all `_id` fields blank.

### Important

- Each catalog row should match **at most one** vendor row. Don't reuse matches.
- If the vendor has duplicate rows (same brand + strain + category), flag them and ask the user.

---

## Output Format

**Your output must be a valid CSV using the exact same columns as `posabit_data.csv`, in the exact same order.**

#{posabit_cols.empty? ? "" : "The output columns are:\n\n```\n#{posabit_cols.join(",")}\n```\n"}
### Rules

- **UPDATE rows**: Keep the `id` and all existing values from the matched catalog row. Only overwrite fields where the vendor row has better/newer data (description, image_url, etc.).
- **NEW rows**: Leave `id` blank. Fill in what you can from the vendor data. Leave ID fields (`brand_id`, `strain_id`, `product_type_id`, `product_family_id`) blank.
- Output the CSV header row first, then one row per product.
- Do not add or remove columns.

### How to tell UPDATE from NEW

| | `id` column | ID fields (`brand_id`, etc.) |
|---|---|---|
| **UPDATE** | Has a value (e.g., `458066`) | Copied from catalog |
| **NEW** | Blank | Blank |

#{field_mapping_text(field_map)}
---

## Workflow

1. Read both CSV files
2. Process the vendor file in batches (50–100 rows at a time)
3. For each batch, output the reconciled CSV rows
4. After all batches, provide a summary: how many updates, how many new products, any duplicates or ambiguous matches
        MD
      end

      private

      def category_mapping_text(mapping)
        return "   *(No category mapping defined for this source)*" if mapping.empty?
        mapping.map { |vendor, posabit| "   - `#{vendor}` → `#{posabit}`" }.join("\n")
      end

      def field_mapping_text(mapping)
        return "" if mapping.empty?

        lines = ["### Vendor-to-POSaBIT field guide", "",
                 "| Vendor Column | POSaBIT Column | Notes |",
                 "|---|---|---|"]
        mapping.each do |m|
          vendor  = m["vendor"]  || m[:vendor]
          posabit = m["posabit"] || m[:posabit]
          notes   = m["notes"]   || m[:notes] || ""
          lines << "| `#{vendor}` | `#{posabit}` | #{notes} |"
        end
        lines << ""
        lines << "For any POSaBIT column not listed above: keep the existing value (for UPDATEs) or leave blank (for NEW)."
        lines.join("\n")
      end
    end
  end
end
