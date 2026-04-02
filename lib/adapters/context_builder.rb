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
        match_hints    = @pipeline["matching_hints"] || {}
        posabit_cols   = @pipeline["posabit_columns"] || []
        cleanup_rules  = @pipeline["name_cleanup_rules"] || []
        cross_cat      = @pipeline["cross_category_matching"] || {}
        disambig       = @pipeline["disambiguating_fields"] || {}
        examples       = @pipeline["matching_examples"] || []

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

---

## Your Job

Merge the vendor products into the POSaBIT catalog.

**Start from `posabit_data.csv` as the base.** Every existing row stays. You are only making changes where the vendor data is newer or better, and appending new products at the bottom.

---

## Matching Rules

For each row in `#{source}_flattened.csv`, search `posabit_data.csv` for a match using these fields in order:

1. **Product category** — Match the vendor's `_product_category` to `product_type_name`:
#{category_mapping_text(cat_mapping)}

2. **Brand name** — Fuzzy match the vendor's brand against `brand_name`. Ignore case and minor differences (e.g., "phat panda" = "Phat Panda").

3. **Strain name** — Fuzzy match the vendor's strain against `strain_name`. Handle minor spelling differences, abbreviations, and missing words.

4. **Weight / Pack Size** — If multiple catalog entries match on category + brand + strain, use weight or pack size to pick the right one.

#{matching_hints_text(match_hints)}
#{disambiguating_fields_text(disambig)}
#{matching_examples_text(examples)}
#{name_cleanup_text(cleanup_rules)}
#{cross_category_text(cross_cat)}
### Canonical Values

**Always use POSaBIT's existing spelling** for `brand_name`, `product_type_name`, and `strain_name`. When a vendor value fuzzy-matches a POSaBIT value, the output must use the POSaBIT version — never the vendor's variant.

Examples:
- Vendor says "Flowers" but POSaBIT has "Flower" → output uses **Flower**
- Vendor says "phat panda" but POSaBIT has "Phat Panda" → output uses **Phat Panda**
- Vendor says "Blue Dreamm" but POSaBIT has "Blue Dream" → output uses **Blue Dream**

This applies to both **update** and **insert** rows. For inserts, if the brand/strain/product_type already exists elsewhere in the catalog, reuse that canonical spelling.

### Decision

- **Match found** → **update**. Keep the entire existing row. Only overwrite fields where the vendor has better/newer data (description, image_url, etc.).
- **Category + Brand match but strain differs** → Check if the catalog `name` contains the vendor's product name or strain. If yes → update. If no → **insert**.
- **No match** → **insert**. Append at the bottom. Leave `id` blank. Fill in what you can from the vendor data.
- **No vendor match** → Existing catalog row with no corresponding vendor row. Keep as-is.

### Important

- Each catalog row should match **at most one** vendor row. Don't reuse matches.
- If the vendor has duplicate rows (same brand + strain + category), flag them and ask the user.
- When in doubt, do NOT update — flag the row for manual review instead.

---

## Output: `reconciliation_output.csv`

Save to: **`data_files/reconciliation_output.csv`**

#{posabit_cols.empty? ? "" : "Use these exact columns in this exact order:\n\n```\n#{posabit_cols.join(",")}\n```\n"}
### Rules

- The output uses the **exact same columns** as `posabit_data.csv`, in the **exact same order**
- Do not remove any existing rows from `posabit_data.csv` — every original row must be in the output
- **Never change the product name** — the `name` column from `posabit_data.csv` is sacred. Never overwrite it with vendor data, even if the vendor has a different name for the same product. For new rows, set `name` from the vendor data.
- **Existing rows**: Keep all values. Only overwrite fields where the vendor has newer data
- **New rows**: Append at the bottom. `id` is blank. Fill in what you can from the vendor data

#{field_mapping_text(field_map)}

### Audit Trail

Add two extra columns at the end:

1. **`row_action`** — the app reads this column to build the reconciliation summary:
   - `none` — existing row with no updates
   - `update` — existing row that was updated with vendor data
   - `insert` — new product from #{source_label} data

2. **`updated_fields`** — comma-separated list of fields that were changed:
   - Existing rows with no updates: *(empty)*
   - Updated rows: e.g. `image_url` or `description, image_url, lineage`
   - New rows: `new product`

These columns are for audit purposes and will not be imported into POSaBIT.

### Reference

See **`sample_result.csv`** in the project root for a concrete example showing the expected output format — including `none`, `update`, and `insert` rows with correct `row_action` and `updated_fields` values.

---

## Workflow

1. Read `posabit_data.csv` — this is your base
2. Read `#{source}_flattened.csv` — these are the incoming products
3. For each vendor row, search the base for a match
4. Build the output: base rows (with updates applied) + new rows appended at the bottom
5. Save `data_files/reconciliation_output.csv`

---

**Please spot check the output before uploading the file to POSaBIT. This is very important.**

#{verification_checklist_text}
        MD
      end

      private

      def category_mapping_text(mapping)
        return "   *(No category mapping defined for this source)*" if mapping.empty?
        mapping.map { |vendor, posabit| "   - `#{vendor}` → `#{posabit}`" }.join("\n")
      end

      def matching_hints_text(hints)
        return "" if hints.nil? || hints.empty?

        lines = ["### Per-category matching notes", ""]
        hints.each do |category, hint|
          lines << "- **#{category}**: #{hint.strip}"
        end
        lines << ""
        lines.join("\n")
      end

      def name_cleanup_text(rules)
        return "" if rules.nil? || rules.empty?

        lines = ["### Product Name Cleanup Rules", "",
                 "Before matching, strip these patterns from vendor Product Names to extract the base strain/product name:", ""]
        rules.each do |rule|
          pattern = rule["pattern"] || rule[:pattern]
          action  = rule["action"]  || rule[:action]
          example = rule["example"] || rule[:example]
          lines << "- **`#{pattern}`**: #{action}"
          lines << "  - Example: #{example}" if example
        end
        lines << ""
        lines.join("\n")
      end

      def cross_category_text(cross_cat)
        return "" if cross_cat.nil? || cross_cat.empty?

        notes = cross_cat.delete("notes") || cross_cat.delete(:notes)
        return "" if cross_cat.empty? && notes.nil?

        lines = ["### Cross-Category Matching", ""]
        cross_cat.each do |dutchie_cat, posabit_cats|
          next unless posabit_cats.is_a?(Array)
          lines << "- **#{dutchie_cat}**: Also search #{posabit_cats.join(", ")} in POSaBIT"
        end
        lines << ""
        lines << notes.strip if notes
        lines << ""
        lines.join("\n")
      end

      def disambiguating_fields_text(fields)
        return "" if fields.nil? || fields.empty?

        lines = ["### Vendor Fields for Disambiguation", "",
                 "The vendor CSV includes these underscore-prefixed fields that are critical for matching variants:", ""]
        fields.each do |field_name, info|
          desc = info["description"] || info[:description] || ""
          lines << "- **`#{field_name}`**: #{desc.strip}"
          values = info["values"] || info[:values]
          if values.is_a?(Hash)
            values.each do |val, explanation|
              lines << "  - `#{val}` — #{explanation.strip}"
            end
          end
        end
        lines << ""
        lines.join("\n")
      end

      def matching_examples_text(examples)
        return "" if examples.nil? || examples.empty?

        lines = ["### Matching Examples", "",
                 "These show how tricky vendor names map to POSaBIT products:", ""]
        examples.each_with_index do |ex, i|
          vendor  = ex["vendor_name"]  || ex[:vendor_name]
          fields  = ex["vendor_fields"] || ex[:vendor_fields]
          posabit = ex["posabit_name"] || ex[:posabit_name]
          action  = ex["action"]       || ex[:action] || "UPDATE"
          reason  = ex["reasoning"]    || ex[:reasoning] || ""
          lines << "#{i + 1}. **Vendor**: `#{vendor}` (#{fields})"
          lines << "   **POSaBIT**: `#{posabit}` → **#{action}**"
          lines << "   **Why**: #{reason.strip}"
          lines << ""
        end
        lines.join("\n")
      end

      def verification_checklist_text
        <<~CHECKLIST
---

## Pre-Submit Verification (Second Pass)

Before finalizing `reconciliation_output.csv`, run these checks:

### 1. INSERT audit

For **every** INSERT row, verify that no existing POSaBIT row shares the same brand + strain in the same (or related) category. If one does, it is almost certainly a variant — convert it to an UPDATE instead.

### 2. Variant field checks

- If `_source_subcategory` is `"small-buds"` → the product belongs to the BB's line. Search POSaBIT for names containing "BB's" + the strain. Do NOT insert.
- If the original vendor name contained `"(DOH Compliant)"` → search POSaBIT for names containing "DOH" + the strain. Do NOT insert.
- If `_parsed_pack_size` has a value → search POSaBIT for that pack size in the product name (e.g., "(0.5gx56)" for pack_size=56). Do NOT insert.

### 3. Duplicate insert check

No two INSERT rows should have the same brand + strain + category. If duplicates exist, keep only the one with the most complete data.

### 4. Lineage sanity check

Do NOT overwrite a more specific POSaBIT lineage with a less specific vendor value:
- `indica_hybrid` → `indica` is a **loss of precision** — keep `indica_hybrid`
- `sativa_hybrid` → `sativa` is a **loss of precision** — keep `sativa_hybrid`
- `hybrid` → `cbd` is a **semantic change** — keep the original unless you are certain
        CHECKLIST
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
