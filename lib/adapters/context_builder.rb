require "csv"

module VendorBridge
  module Adapters
    class ContextBuilder
    def initialize(pipeline)
      @pipeline = pipeline
    end

    def generate
      vendor_rows      = @pipeline["rows"]
      vendor_columns   = @pipeline["columns"]
      posabit_rows     = @pipeline["posabit_rows"]
      posabit_cols     = @pipeline["posabit_columns"]
      source_label     = @pipeline["source_label"] || @pipeline["source"]
      filename         = @pipeline["filename"]
      cat_mapping      = @pipeline["category_mapping"] || {}
      field_map        = @pipeline["field_mapping"] || []

      brands        = posabit_rows.map { |r| r["brand_name"] }.compact.uniq.sort
      product_types = posabit_rows.map { |r| r["product_type_name"] }.compact.uniq.sort

      vendor_brands = vendor_rows.map { |r| r["Brand"] }.compact.uniq.sort
      vendor_cats   = vendor_rows.map { |r| r["_product_category"] }.compact.uniq.sort

      <<~MD
# POSaBIT Product Reconciliation — Context File

> Load this entire file into your AI assistant as context.
> Then paste rows from your flattened vendor CSV one at a time (or in small batches) and ask the assistant to match them.

---

## Your Role

You are a product data reconciliation assistant. You have the store's current POSaBIT product catalog loaded below. The user will paste incoming vendor product rows one at a time or in small batches from their **#{source_label}** export.

For each incoming row, determine whether it matches an existing product in the catalog (UPDATE) or is brand new (NEW).

---

## Matching Rules

For each incoming vendor product, search the POSaBIT catalog below using these fields **in order of priority**:

1. **Product category** — Match the vendor's `_product_category` to the catalog's `product_type_name`:
#{category_mapping_text(cat_mapping)}

2. **Brand name** — Fuzzy match the vendor's `Brand` against `brand_name`. Ignore case and minor differences (e.g., "phat panda" = "Phat Panda").

3. **Strain name** — Fuzzy match the vendor's `Strain` against `strain_name`. Handle minor spelling differences, abbreviations, and missing words.

4. **Weight / Pack Size** — If multiple catalog entries match on category + brand + strain, use weight or pack size to pick the right one.

### Decision

- **All 3 match** (+ weight if applicable) → it's an **UPDATE**. Copy the entire matching row from the catalog, then update only the fields that have new data from the vendor row (description, image, weight, etc.). Keep the `id` and all ID fields (`brand_id`, `strain_id`, `product_type_id`, `product_family_id`) from the catalog.
- **Category + Brand match but strain is different/missing** → Check if the `name` field in the catalog contains the vendor's product name or strain. If yes → UPDATE. If no → **NEW**.
- **No match on category + brand** → it's **NEW**. Leave `id` blank. Leave all `_id` fields blank.

### Important

- Each catalog row should match **at most one** incoming vendor row. If you've already matched a catalog entry, don't match it again.
- If the vendor has duplicate rows (same brand + strain + category), flag them and ask the user.

---

## Output Format

**CRITICAL: Your output must be a valid CSV file using the exact same columns as the POSaBIT catalog below, in the exact same order.**

The output columns are:

```
#{posabit_cols.join(",")}
```

### Rules

- **UPDATE rows**: Keep the `id` and all existing values from the matched catalog row. Only overwrite fields where the vendor row has better/newer data (e.g., description, image_url).
- **NEW rows**: Leave `id` blank. Fill in what you can from the vendor data. Leave ID fields (`brand_id`, `strain_id`, `product_type_id`, `product_family_id`) blank — POSaBIT will assign them on import.
- **Always output the CSV header row first**, then one row per product.
- **Do not add or remove columns.** The output must have exactly #{posabit_cols.size} columns, matching the catalog format.

### How to tell UPDATE from NEW in the output

| | `id` column | ID fields (`brand_id`, etc.) |
|---|---|---|
| **UPDATE** | Has a value (e.g., `458066`) | Copied from catalog |
| **NEW** | Blank | Blank |

---

## Current POSaBIT Catalog (#{posabit_rows.size} products)

**Brands:** #{brands.join(", ")}
**Product types:** #{product_types.join(", ")}

```csv
#{posabit_csv_block(posabit_cols, posabit_rows)}
```

---

## Incoming Vendor Data Format

**Source:** #{source_label} (#{filename})
**Total products:** #{vendor_rows.size}
**Brands:** #{vendor_brands.first(20).join(", ")}#{vendor_brands.size > 20 ? " (and #{vendor_brands.size - 20} more)" : ""}
**Categories:** #{vendor_cats.join(", ")}

The user will paste rows with these columns:

```
#{vendor_columns.join(",")}
```

#{field_mapping_text(field_map)}
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

    def posabit_csv_block(columns, rows)
      lines = [columns.join(",")]
      rows.each do |row|
        lines << columns.map { |c| csv_escape(row[c]) }.join(",")
      end
      lines.join("\n")
    end

    def csv_escape(value)
      return "" if value.nil?
      s = value.to_s
      if s.include?(",") || s.include?('"') || s.include?("\n")
        '"' + s.gsub('"', '""') + '"'
      else
        s
      end
    end
  end
  end
end
