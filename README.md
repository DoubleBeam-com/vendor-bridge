# Vendor Bridge

![CI](https://github.com/DoubleBeam-com/vendor-bridge/actions/workflows/ci.yml/badge.svg)
![Lint](https://github.com/DoubleBeam-com/vendor-bridge/actions/workflows/lint.yml/badge.svg)

Clean up your product export files and get them ready to import into POSaBIT.

Your data stays on your computer the entire time — nothing is uploaded to the internet.

---

## Setup (one time)

### Mac

Open **Terminal** (search for "Terminal" in Spotlight) and paste these commands one at a time:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

```
brew install ruby git
```

```
git clone https://github.com/DoubleBeam-com/vendor-bridge.git
```

```
cd vendor-bridge && bundle install
```

### Windows

1. Download and install Ruby from [rubyinstaller.org](https://rubyinstaller.org/) (pick the latest version with Devkit)
2. Download and install Git from [git-scm.com](https://git-scm.com/download/win)
3. Open **Start Menu**, search for **"Ruby"**, and open **"Start Command Prompt with Ruby"**
4. Paste these commands one at a time:

```
git clone https://github.com/DoubleBeam-com/vendor-bridge.git
```

```
cd vendor-bridge && bundle install
```

---

## How to Use

### Step 1 — Start the tool

Open Terminal (Mac) or the Ruby Command Prompt (Windows) and run:

```
cd vendor-bridge
bundle exec puma config.ru -p 4567
```

You should see a message that says the server is running. Leave this window open.

### Step 2 — Open in your browser

Go to: **http://localhost:4567**

### Step 3 — Upload your file

1. Pick your source system from the dropdown (e.g. **iHeartJane**)
2. Drag your Excel file onto the upload area (or click to browse)
3. Click **Flatten & Preview**

### Step 4 — Check the results

You'll see a summary of how many products were found in each category. Make sure the numbers look right.

### Step 5 — Download the flattened CSV

Click **Download Flattened CSV**. This is your clean product data in a single file.

### Step 6 — Match against your POSaBIT catalog (optional)

If you want the tool to help you figure out which products are new vs. updates:

1. Upload your current POSaBIT product export (CSV) on the same page
2. Click **Download Context File**
3. Open [Claude Cowork](https://cowork.claude.ai)
4. Open the **data_files** folder and attach the **context file** to the conversation
5. Ask Claude to review and reconcile the data
6. Claude will create two files in `data_files/`:
   - **reconciliation_output.csv** — the import-ready file (rows with an `id` are updates, blank `id` means new)
   - **reconciliation_summary.md** — a summary showing how many products were updated, how many are new, and any flagged items
7. **Review the summary and spot check the output before uploading to POSaBIT**

### When you're done

Go back to Terminal and press **Ctrl + C** to stop the tool.

---

## Supported Formats

| Source | File Type |
|---|---|
| **iHeartJane** | Excel (.xlsx) — the Product Configuration Template |

More sources will be added over time.

---

## What gets cleaned up?

The tool automatically:

- Reads all product sheets (Flower, Pre-Roll, Edible, Concentrate, Vape, Topical, Gear, Merchandise)
- Skips the instruction and example pages
- Removes the placeholder rows ("My Brand", "My Strain")
- Removes section headers and empty rows
- Combines everything into one flat file with one row per product
- Keeps all your data: brand, strain, category, description, images, and everything else

---

## Privacy

Everything runs locally on your computer. Your product data is never sent to any server or third party.

---

## Something not working?

| Problem | Fix |
|---|---|
| `bundle install` shows an error | Make sure Ruby is installed: run `ruby --version` — you need 3.1 or newer |
| Browser says "can't connect" | Make sure the terminal window is still running and shows no errors |
| Port already in use | Try a different port: `bundle exec puma config.ru -p 3000` then go to http://localhost:3000 |
| Excel file not recognized | Save as `.xlsx` format (not `.xls`). The file must be Excel 2007 or newer |
| Products are missing | The tool removes rows with a blank Brand column. Make sure your products have a brand filled in |

Still stuck? Open an issue at [github.com/DoubleBeam-com/vendor-bridge/issues](https://github.com/DoubleBeam-com/vendor-bridge/issues)

---

## For Developers & AI Assistants

See [docs/architecture.md](docs/architecture.md) for full project architecture, the rosetta stone config, and how to add new sources.

---

## License

MIT
