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

> Open this file in [Claude Cowork](https://cowork.claude.ai) or any AI assistant.
> All data files are in the same `data_files/` folder as this file.

---

## Files

All files are in the **`data_files/`** folder:

| File | Description |
|---|---|
| `#{source}_flattened.csv` | Incoming vendor products from #{source_label} |
| `posabit_data.csv` | Current POSaBIT catalog (this is your starting point) |
| `reconciliation_output.csv` | **You will create this** — the final import-ready file |
| `reconciliation_summary.md` | **You will create this** — summary of changes |

---

## Your Job

Merge the vendor products into the POSaBIT catalog.

**Start from `posabit_data.csv` as the base.** Every existing row stays. You are only making changes where the vendor data is newer or better, and appending new products at the bottom.

---

## Matching Rules

For each row in `#{source}_flattened.csv`, search `posabit_data.csv` for a match using these fields in order:

1. **Product category** — Match the vendor's `_product_category` to `product_type_name`:
#{category_mapping_text(cat_mapping)}

2. **Brand name** — Fuzzy match the vendor's `Brand` against `brand_name`. Ignore case and minor differences (e.g., "phat panda" = "Phat Panda").

3. **Strain name** — Fuzzy match the vendor's `Strain` against `strain_name`. Handle minor spelling differences, abbreviations, and missing words.

4. **Weight / Pack Size** — If multiple catalog entries match on category + brand + strain, use weight or pack size to pick the right one.

### Decision

- **Match found** → **UPDATE**. Keep the entire existing row. Keep `id` and all ID fields (`brand_id`, `strain_id`, `product_type_id`, `product_family_id`). Only update fields where the vendor has better/newer data (description, image_url, etc.).
- **Category + Brand match but strain differs** → Check if the catalog `name` contains the vendor's product name or strain. If yes → UPDATE. If no → **NEW**.
- **No match** → **NEW**. Append at the bottom. Leave `id` and all `_id` fields blank. Fill in what you can from the vendor data.

### Important

- Each catalog row should match **at most one** vendor row. Don't reuse matches.
- If the vendor has duplicate rows (same brand + strain + category), flag them and ask the user.
- When in doubt, do NOT update — flag the row for manual review instead.

---

## Output: `reconciliation_output.csv`

Save to: **`data_files/reconciliation_output.csv`**

#{posabit_cols.empty? ? "" : "Use these exact columns in this exact order:\n\n```\n#{posabit_cols.join(",")}\n```\n"}
### Rules

- The file must use the **exact same columns** as `posabit_data.csv`, in the **exact same order**
- **UPDATE rows**: Keep `id` and all existing values. Only overwrite fields where the vendor has newer data
- **NEW rows**: Append at the bottom. `id` is blank. All `_id` fields are blank
- Do not add or remove columns
- Do not remove any existing rows from `posabit_data.csv` — every original row must be in the output

#{field_mapping_text(field_map)}

---

## Output: `reconciliation_summary.md`

Save to: **`data_files/reconciliation_summary.md`**

After completing the reconciliation, create a summary with:

- **Total products** in the output file
- **Unchanged** — existing products with no modifications
- **Updated** — existing products where fields were changed (list what changed per product)
- **New** — products not found in the catalog (list each one)
- **Flagged** — ambiguous matches or duplicates that need manual review

This summary helps the vendor understand the blast radius of the import before uploading.

---

## Workflow

1. Read `posabit_data.csv` — this is your base
2. Read `#{source}_flattened.csv` — these are the incoming products
3. For each vendor row, search the base for a match
4. Build the output: base rows (with updates applied) + new rows appended at the bottom
5. Save `data_files/reconciliation_output.csv`
6. Save `data_files/reconciliation_summary.md`

---

**Please spot check the output before uploading the file to POSaBIT. This is very important.**
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
