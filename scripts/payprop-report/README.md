# PayProp Portfolio Health Check report

Regenerates the "Portfolio Health Check" report (matching the original CSM
Excel template) for **Invitation Homes Management (Pty) Ltd**, pulled live
from the connected PayProp account.

## How it's triggered

Conversationally: ask Claude ("generate the health check report") in a
Claude Code session that has the PayProp connector attached. There is no
separate backend or scheduled job -- the trigger *is* the chat request.

## How it works -- hybrid live + manual-upload

Two of the seven data tabs are pulled **live** every time, via the PayProp
MCP connector:

- **ICDN** (`payprop_get_icdn`, `payprop_normalize.normalize_icdn`)
- **Active Beneficiaries** (`payprop_get_beneficiaries`,
  `payprop_normalize.normalize_active_beneficiaries`)

The other five must come from a **manually exported PayProp CSV**, because
the connector either has no bulk endpoint for that data or times out
without a `property_id`/`tenant_id` filter (confirmed: `tenant_balances`
alone would need 500+ sequential per-property calls -- not viable per
request):

| Tab | PayProp export |
|---|---|
| All Tenants | Reports → Tenants, Beneficiaries & Properties → Report Type `Tenants All` (tick "Include archived tenants") |
| Arrears | Tenants → Arrears Analysis |
| Beneficiary Balances | Dashboard → Outgoing payments window |
| Expired Contracts | Dashboard → Contracts window → Expired contracts |
| All Payments | Reports → Transaction history, filtered by Remittance date |

`generate_report.py` ties it together: it reads the two live JSON dumps
(from the MCP calls made in the same chat turn -- only Claude can call MCP
tools, a subprocess can't) plus the uploaded CSVs, via
`payprop_normalize.load_csv_rows()`, and calls `build_workbook(...)`.

Beneficiary Balances and All Payments are optional (`--beneficiary-
balances-csv` / `--all-payments-csv`); when omitted, the affected tab and
the 3 dependent Summary metrics (#23, #24, #25) are marked "N/A - awaiting
API access" rather than silently showing zero.

The output path is reused and overwritten on every request -- this tool
never accumulates dated copies.

### Open assumption to validate

`normalize_active_beneficiaries()` treats a beneficiary as "active" when
`is_owner` is true and it has at least one property assignment, and derives
`BenStatus` from `is_active_owner` -- the API has no direct status string
matching the CSV export's own values, so this is a best-effort mapping that
hasn't yet been checked against a real Active Beneficiaries CSV export
side-by-side. Commission/Amount/PropertyAmount also aren't in this API's
response shape and are left blank (no Summary formula reads them, so this
is cosmetic only).

## Why cached formula values are computed in Python

Every Summary cell is written as both a real Excel formula (so the workbook
keeps working if someone edits data by hand later) and a pre-computed cached
value, via `xlsxwriter`'s `write_formula(..., value=...)`. Normally you'd
let LibreOffice recalculate the file after writing it, but headless
LibreOffice macro execution hangs indefinitely in this environment (verified
independent of file size/content -- see conversation history). Computing
values in Python (`compute_metrics()`) and validating them against the
original template's known-correct numbers sidesteps that, and all 24
computable metrics were confirmed to match the original file exactly.

## Preserved template quirks

- Metric #5 "Total Tenants in arrears" (`COUNTA(Arrears!B:B)`) counts the
  header row along with the data, exactly like the original template. This
  is a known off-by-one in the source template, kept intentionally for
  fidelity -- the recommendation text below it uses the corrected count.
- Metric #14 "Inactive/Archived tenants with Deposits" originally had a
  `-1` in its formula to offset a full-column reference matching its own
  header row; since this build always uses row-bounded ranges (no header in
  range), that offset is correctly omitted here.

## Recommendations panel

Only recommendations that are a **direct, mechanical restatement of a
metric** (e.g. "9 active tenants have deposits under 100%") are
auto-generated. Findings that require business context PayProp's data can't
supply (e.g. "this beneficiary is an admin fee account", "these are
storerooms") are intentionally left for manual review rather than
fabricated.
