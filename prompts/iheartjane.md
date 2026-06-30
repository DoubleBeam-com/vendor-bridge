# iHeartJane → POSaBIT Prompt

> **What this is:** a self-contained prompt that does everything the Vendor Bridge
> app does for an iHeartJane product template — without anyone needing to run the
> app. Paste the prompt below into [Claude Cowork](https://cowork.claude.ai),
> attach the files, and it will produce the clean, import-ready CSV.

---

## How to use it (for non-technical users)

1. Open Claude Cowork.
2. Attach your **iHeartJane product template** (`.xlsx`) — the original Excel file
   from iHeartJane, not a CSV.
3. *(Optional)* Attach your current **POSaBIT catalog export** (`.csv`) if you want
   the products merged into your existing catalog. If you don't have one, skip it —
   the prompt will just produce the clean product CSV.
4. Copy everything in the **"PROMPT — copy from here"** box below and send it.
5. When it finishes, download the files it created.

That's it. You don't need to install anything or run any code.

---

## PROMPT — copy from here ⬇️

````
You are converting an iHeartJane product template into a clean, POSaBIT
import-ready CSV. Follow these rules exactly. Do not skip steps.

I have attached:
- An iHeartJane product template (.xlsx) — REQUIRED.
- A POSaBIT catalog export (.csv), named something like "Core Products ....csv"
  — OPTIONAL. If it is present, do the reconciliation in PART 2. If it is NOT
  present, stop after PART 1 and give me the flattened CSV.

================================================================
PART 1 — FLATTEN THE iHEARTJANE EXCEL
================================================================

Goal: read every product sheet in the workbook and produce one combined CSV
called `iheartjane_flattened.csv`, one row per real product.

### 1a. Which sheets to read

Read ONLY these sheets. Map each sheet name to a product category:

| Excel sheet name          | Category (_product_category) |
|---------------------------|------------------------------|
| Flower                    | Flower                       |
| Pre-RollInfused           | Preroll                      |
| Edible                    | Edible                       |
| Extract (concentrates)    | Concentrate                  |
| Vape                      | Vape                         |
| Topical                   | Topical                      |
| Gear                      | Gear                         |
| Merch.                    | Merchandise                  |

IGNORE every other sheet, especially "Intructions" (note the misspelling) and
"Product Card". If a sheet in the list is missing, just skip it.

If NONE of the sheets above exist in the workbook, stop and tell me the file
does not look like an iHeartJane product template.

### 1b. Reading the header row

- Row 1 of each sheet is the header row. Product rows start on row 2.
- On the **Flower** sheet only, the first column header is blank — treat that
  first column as **"Brand"**.
- Drop any trailing empty header columns (some sheets have blank columns on the
  right).
- Trim leading/trailing whitespace from every header name.

### 1c. Which rows to KEEP (row filtering)

For each row below the header, DROP the row if ANY of these are true:

1. **Example/template row** — the Brand is exactly "My Brand" (case-insensitive),
   OR the Strain / "Ratio & Product Name" is exactly "My Strain" or "My Product".
2. **Empty row** — every data cell is blank. (When checking "empty", ignore these
   helper columns: "Jane Use: Click here when product is added", "Jane Use",
   "Product Name (Internal Use)", "Product Name".)
3. **Section header row** — the Brand is blank AND at most one other data cell is
   filled (these are dividers like "CORE PREROLLS" or "Sticky Frog Cake Batter").
4. **Pipe-only name** — the "Product Name (Internal Use)" / "Product Name" cell
   contains only pipes and spaces (e.g. " | | | ").
5. **Blank brand** — the Brand cell is empty.

Keep every other row. These are real products.

### 1d. Add these columns to every kept row

- `_source_sheet` — the Excel sheet name the row came from.
- `_product_category` — the mapped category from the table in 1a.
- `_source_row` — the Excel row number (for traceability).
- `_cover_image_url` — see 1e.
- `_old_cover_image_url` — see 1e.

### 1e. Image URLs

- The image column is the one whose header contains "image" (e.g. "IMAGE LINK
  ONLY ..."). In Excel these are often stored as hyperlinks — use the hyperlink
  target if the visible cell text isn't a URL.
- `_cover_image_url` = the first value in any image-like column that starts with
  `http://` or `https://`. If none, leave it blank.
- **Google Drive cleanup:** if `_cover_image_url` is a Google Drive *view/share*
  link, rewrite it to the direct form and save the ORIGINAL into
  `_old_cover_image_url`. Otherwise leave `_old_cover_image_url` blank.
  - `https://drive.google.com/file/d/FILE_ID/view?usp=sharing` → `https://drive.google.com/uc?export=view&id=FILE_ID`
  - `https://drive.google.com/open?id=FILE_ID` → `https://drive.google.com/uc?export=view&id=FILE_ID`
  - Links that already end in an image extension (.jpg/.png/.webp/etc.) or are
    already in `uc?export=view&id=` / `drive.usercontent.google.com/download`
    form: leave untouched.
  - Non-Google-Drive URLs: leave untouched.

### 1f. Write `iheartjane_flattened.csv`

- Columns: put the five underscore columns first, in this order —
  `_source_sheet, _product_category, _source_row, _cover_image_url,
  _old_cover_image_url` — then every other column found across the sheets, sorted
  alphabetically. (Different sheets have different columns; union them. Leave a
  cell blank when a row's sheet doesn't have that column.)
- One row per kept product.

If no POSaBIT catalog was attached, STOP here and give me
`iheartjane_flattened.csv` plus a one-line count of products per category.

================================================================
PART 2 — RECONCILE AGAINST THE POSaBIT CATALOG
================================================================

Only do this if a POSaBIT catalog CSV was attached.

Base = the POSaBIT catalog. **Every existing row stays.** You are updating rows
where the iHeartJane data is newer/better, and appending genuinely new products
at the bottom. Output = `reconciliation_output.csv`, using the EXACT same columns
in the EXACT same order as the POSaBIT catalog, plus four audit columns at the end.

The POSaBIT catalog's own header row is authoritative for column names and order —
copy it exactly. A standard POSaBIT export looks like this (yours may differ
slightly; if so, follow yours):

```
id,active,sku_reference,name,display_name,brand_name,product_type_name,concentrate_type,strain_name,lineage,weight,weight_unit,pack_size,cost,min_reorder_qty,terpenes,effects,flavors,description,instructions,ingredients,cover_image_url,image_urls,quantity_on_hand
```

### 2a. Matching — for each flattened iHeartJane row, find its POSaBIT match

Match in this order:

1. **Category** — map `_product_category` to POSaBIT `product_type_name`:
   - `Flower` → `Flower`
   - `Preroll` → `Preroll`
   - `Edible` → `Edible Solid` or `Edible Liquid` (capsules → Edible Solid;
     tinctures/drinks → Edible Liquid)
   - `Concentrate` → `Concentrate` (or `BHO`)
   - `Vape` → `Cartridge`
   - `Topical` → `Topical`
   - `Gear` → no POSaBIT match — almost always a NEW insert; flag for review
   - `Merchandise` → no POSaBIT match — almost always a NEW insert; flag for review
2. **Brand** — fuzzy match the iHeartJane Brand against `brand_name` (ignore case
   and minor differences: "phat panda" = "Phat Panda").
3. **Strain** — fuzzy match against `strain_name` (handle spelling differences,
   abbreviations, missing words).
4. **Weight / Pack Size** — if several catalog rows match on category+brand+strain,
   use weight or pack size to pick the right one.

**Per-category matching notes:**
- **Flower** — no weight or product name is available on this sheet, so match on
  brand + strain only. If multiple catalog rows match (different weights), apply
  the description and image to ALL of them (bulk-apply).
- **Concentrate** — match on brand + strain + weight (all three are available).
- **Preroll** — match on brand + strain + weight. This sheet has both regular and
  infused prerolls — check for "infused" in the product name to keep them as
  different product types.
- **Edible** — capsules → Edible Solid; tinctures → Edible Liquid.
- **Vape** — the "Ratio & Product Name" column holds the STRAIN, not the product
  name. Match on brand + strain.
- **Topical** — usually very few rows; match on name if possible, otherwise flag
  for manual review.
- **Gear / Merchandise** — no core products in POSaBIT; these are almost always
  INSERTs. Flag for manual review.

### 2b. Canonical values

Always output POSaBIT's existing spelling for `brand_name`, `product_type_name`,
and `strain_name`. When a vendor value fuzzy-matches a POSaBIT value, use the
POSaBIT version (e.g. vendor "Flowers" → output "Flower"; vendor "phat panda" →
output "Phat Panda"). Applies to updates AND inserts.

### 2c. Decision

- **Match found** → **update**. Keep the whole existing row; only overwrite fields
  where iHeartJane has better/newer data (description, cover_image_url, etc.).
- **Category + brand match but strain differs** → if the catalog `name` contains
  the vendor's product name/strain, update; otherwise insert.
- **No match** → **insert**. Append at the bottom, leave `id` blank, fill what you
  can from the vendor data.
- **No vendor row for a catalog row** → keep it exactly as-is (`row_action = none`).

Each catalog row matches at most one vendor row — don't reuse a match. If the
vendor file has duplicate rows (same brand+strain+category), flag them and ask me.
When in doubt, do NOT update — flag for manual review.

### 2d. Field guide (iHeartJane column → POSaBIT column)

| iHeartJane column        | POSaBIT column      | Notes |
|--------------------------|---------------------|-------|
| Brand                    | brand_name          | also used for matching |
| Strain                   | strain_name         | also used for matching |
| _product_category        | product_type_name   | via the category map in 2a |
| Product Name             | name, display_name  | for new rows only — NEVER overwrite an existing `name` |
| Product Description      | description         | see weight-in-description note below |
| Pack Size                | pack_size           | |
| Amount [g]               | weight              | also check Total Weight = Amount × Pack Size |
| _cover_image_url         | cover_image_url     | ALWAYS update when it starts with http, even if POSaBIT already has an image |
| _old_cover_image_url     | old_cover_image_url | audit only — do not import |
| Product Name             | source_name         | raw vendor name, for the audit column |

For any POSaBIT column not listed: keep the existing value (updates) or leave
blank (new rows).

**`name` is sacred** — never change the `name` of an existing POSaBIT row, even if
the vendor calls the product something different. Only set `name` from vendor data
on brand-new insert rows.

**Description weights:** vendors often write one description per SKU and POSaBIT
bulk-applies it across weight variants, leaving the wrong weight in all but one
row. When a description references a portion-size weight that doesn't match the
row's actual `weight`/`pack_size`, fix it. Three cases:
1. **Single weight token** — rewrite "7g jar" → "{weight}g jar".
2. **Pack-and-unit form** ("Nct of Mg prerolls") — keep the per-unit weight (M)
   and recompute the count N as weight ÷ M; drop the count if it doesn't divide
   evenly.
3. **Vernacular weights** — translate eighth = 3.5g, quarter = 7g, half = 14g,
   ounce = 28g to the row's actual weight.
Only touch weight tokens describing the product's portion size. Leave weight
references about lineage, history, ingredients, or batch sizes alone. If there's
no weight reference, leave the description untouched.

### 2e. Concentrate type (Concentrate, BHO, Cartridge only)

`concentrate_type` is NOT a direct field — infer it by scanning the Product Name
for one of these canonical values (use the exact spelling):
Live Resin, BHO, Wax, Sugar Wax, RSO, Crumble, Rosin, Shatter, Distillate,
Cured Resin, Bubble Hash, Diamonds, Badder, Sauce.

- Only set it for products whose final `product_type_name` is Concentrate, BHO,
  or Cartridge. NEVER set it on Flower, Preroll, Edible Solid, Edible Liquid,
  Topical, or Accessories — if such a row already has a value, clear it to blank.
- Only fill it when the matched POSaBIT row's `concentrate_type` is blank — never
  overwrite an existing value. If uncertain, leave blank.

### 2f. Cross-category / product-type correction

If a vendor row matches a POSaBIT row in a different category (cross-category
match), correct `product_type_name` on the output row to match the vendor's
mapped category, and add `product_type_name` to `updated_fields`. Confirmations:
product name contains "Capsule"/"Capsules" → Edible Solid; "Tincture" → Edible
Liquid; "Drink"/"Beverage"/"RTM" → Edible Liquid. Capsules and tinctures are
different forms — never mix them; flag any cross-form match for review.

### 2g. Audit columns (add these four at the END, after the POSaBIT columns)

1. **`row_action`** — `none`, `update`, or `insert`.
2. **`updated_fields`** — comma-separated changed fields (e.g.
   `description, cover_image_url`); empty for `none`; `new product` for inserts.
3. **`warnings`** — set when any of these apply (comma-separate multiple):
   - `capsule/tincture mismatch` — vendor form differs from the POSaBIT row's
     form on an edible; correct product_type_name, then apply the image.
   - `lineage precision loss` — new lineage is less specific than existing
     (e.g. indica_hybrid → indica); KEEP the more specific original.
   - `cross-category match` — matched a row in a different category; verify it's
     legitimate.
   - `possible strain mismatch` — strain doesn't fuzzy-match after cleanup; do
     NOT update — convert to insert or flag.
   - `concentrate_type inferred` — value was guessed from the name; verify.
   - Leave blank when nothing applies.
4. **`source_name`** — the iHeartJane `Product Name` from the vendor row that drove
   the change (for update and insert rows; empty for `none`).

These four columns are for audit only and won't be imported into POSaBIT.

### 2h. Output files

- `reconciliation_output.csv` — the import-ready file (POSaBIT columns in order +
  the four audit columns).
- `reconciliation_summary.md` — a short human-readable summary: counts of
  none/update/insert per product type, the list of updates with their changed
  fields, and the list of inserts.

================================================================
FINAL CHECK (do this before you hand me the files)
================================================================

1. **INSERT audit** — for every insert, confirm no existing POSaBIT row shares the
   same brand + strain in the same/related category. If one does, it's a variant —
   make it an update instead.
2. **No duplicate inserts** — no two inserts share brand + strain + category.
3. **Lineage** — never replaced a more specific lineage with a vaguer one
   (`indica_hybrid` → `indica` and `sativa_hybrid` → `sativa` are precision loss;
   `hybrid` → `cbd` is a semantic change — keep the original unless certain).
4. **Concentrate type guard** — no Flower/Preroll/Edible/Topical/Accessories row
   has a concentrate_type.
5. **Row count** — every original POSaBIT row is still present in the output.
6. **`name` untouched** — no existing POSaBIT `name` was changed.

Please spot-check the output before uploading to POSaBIT. This is important.
````

---

## ⬆️ PROMPT — copy to here

This prompt mirrors the Vendor Bridge pipeline: PART 1 reproduces the iHeartJane
adapter + row filter + Google Drive image cleanup (`lib/adapters/iheartjane_v1.rb`,
`lib/transforms/`), and PART 2 reproduces the reconciliation context the app
generates from `config/rosetta_stone.yaml`. If the iHeartJane template or the
mappings change in the app, update this prompt to match.
