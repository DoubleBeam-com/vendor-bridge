# vendor-bridge — Product Spec

## What it is

An open source, locally-run tool that takes a messy third-party product export and converts it into a clean CSV file ready to import into the PosabiT portal. It uses an LLM to handle the field matching so no hard-coded column mapping is needed on our end.

---

## Who runs it

Either a vendor running it on their own machine, or PosabiT staff running it on a vendor's behalf. The tool must work for both cases without any configuration changes.

---

## How it runs

- A Ruby script starts a local web server (Sinatra)
- The user opens a browser to `http://localhost:4567`
- Everything runs on the user's machine — no data is sent anywhere except to the chosen LLM API
- It is open source and distributed as a GitHub repo

---

## LLM API key configuration

The API key is saved to a local config file so the user does not have to paste it every time. The config file lives in the project root.

The tool also supports a `.claude` file in the project root for use with Claude Cowork, so PosabiT staff running the tool through Cowork do not need to touch the config manually.

Supported providers: **OpenAI, Anthropic (Claude), Gemini**. The user selects their provider and pastes their key once. It is saved locally after that.

---

## Input

- **Format:** XLSX (Excel file, multiple tabs)
- **Source (v1):** iHeartJane menu export
- The Excel file from iHeartJane is messy — multiple tabs, inconsistent structure. The tool needs to identify which tab(s) contain product data and extract the relevant rows.

---

## Processing pipeline

### Step 1 — Upload
The user uploads the XLSX file through the browser UI and selects the source system (iHeartJane).

### Step 2 — Flatten
Before any AI is involved, a source-specific adapter runs deterministic logic to:
- Identify the correct tab(s) in the Excel file
- Extract product rows
- Flatten any nested or multi-column structures into a simple flat row per product

This step is rule-based, not AI. The output is a clean, flat table the LLM can reason about.

### Step 3 — Preview
The user sees the first several rows of the flattened data in the browser before anything is sent to the LLM. This is a sanity check step — no action required, just a confirmation to continue.

### Step 4 — AI field matching
The tool sends a sample of the flattened data plus the PosabiT target schema to the LLM. The LLM runs three prompts in sequence:

1. **Detect** — identify what each source field appears to represent
2. **Match** — map each source field to the correct PosabiT field
3. **Audit** — flag any fields the LLM is uncertain about

The result is a proposed field mapping plus a list of uncertain fields with notes.

### Step 5 — Human review
The proposed mapping is shown to the user as an editable form. Each PosabiT field has a dropdown of available source fields. Fields flagged as uncertain by the LLM are highlighted so the user knows where to focus. The user can correct any mapping before proceeding.

### Step 6 — Export
The user confirms the mapping. The tool applies it to all rows and produces a CSV file formatted exactly as PosabiT's import portal expects. The user downloads the CSV and imports it manually into the portal.

---

## Output

- A single **CSV file** matching the PosabiT product import format
- One row per product
- Column names match PosabiT's import template exactly

---

## PosabiT target schema (v1)

The fields the output CSV must contain:

| Field | Description |
|---|---|
| product_id | Unique identifier |
| product_name | Display name |
| brand_name | Brand or cultivator |
| category | Top-level category (Flower, Edible, etc.) |
| subcategory | Specific type (Pre-Roll, Gummy, etc.) |
| strain_type | Indica / Sativa / Hybrid / CBD |
| description | Product description text |
| unit_price | Price in dollars |
| unit_of_measure | gram, eighth, each, etc. |
| thc_percentage | THC % |
| cbd_percentage | CBD % |
| image_url | URL to product image |
| is_available | true / false |
| sku | Vendor SKU |

---

## Source adapters

### iHeartJane (v1)
- Input is a multi-tab XLSX file
- The adapter identifies the product tab, extracts rows, and flattens the structure into the fields above as best it can before handing off to the LLM
- The LLM handles anything the adapter cannot determine with certainty

### Future sources
Adding a new source means adding a new adapter file. The rest of the pipeline does not change.

---

## What this spec does not cover (decisions still needed)

- The exact tab name or structure of the iHeartJane XLSX (needs a real sample file to define the adapter rules)
- Whether the saved config file is encrypted or plain text
- Error handling UX (what the user sees if the XLSX has no recognizable product data, or the LLM call fails)
- Whether the confirmed mapping is saved for re-use on the next run
