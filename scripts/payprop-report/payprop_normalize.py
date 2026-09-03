"""
Turns PayProp MCP tool output / manually-exported CSVs into the row shape
build_report.py expects (lists of values in the same column order as
PayProp's own CSV exports -- see the *_HEADERS constants there).

Two data sources per tab type:
  - normalize_icdn() / normalize_active_beneficiaries(): from live MCP calls
    (payprop_get_icdn, payprop_get_beneficiaries). These paginate cleanly
    and don't hit the per-property bottleneck that blocks tenant_balances.
  - load_csv_rows(): for the 5 tabs that must come from a manually exported
    PayProp CSV (All Tenants, Arrears, Beneficiary Balances, Expired
    Contracts, All Payments) -- see README.md for why.
"""
from __future__ import annotations

import csv
import datetime

from build_report import ACTIVE_BENEFICIARIES_HEADERS, ARREARS_HEADERS, ICDN_HEADERS


def _bool_to_yn(v) -> str:
    return "Y" if v else "N"


def _flt(v, default=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def normalize_icdn(items: list[dict]) -> list[list]:
    """payprop_get_icdn items -> ICDN tab rows.

    Only PropertyID/Property/Date/Type/Amount are used by any Summary
    formula (Type feeds metrics #18-20). Agent/VAT/RefNo/CustomerRef* aren't
    present in this API's response shape, so those columns are left blank --
    cosmetic gaps only, they don't affect any computed metric.
    """
    rows = []
    for it in items:
        prop = it.get("property") or {}
        tenant = it.get("tenant") or {}
        category = it.get("category") or {}
        row = [None] * len(ICDN_HEADERS)
        row[ICDN_HEADERS.index("PropertyID")] = prop.get("id")
        row[ICDN_HEADERS.index("Property")] = prop.get("name")
        row[ICDN_HEADERS.index("Date")] = it.get("date")
        row[ICDN_HEADERS.index("Type")] = (it.get("type") or "").title()
        row[ICDN_HEADERS.index("InvoiceType")] = category.get("name")
        row[ICDN_HEADERS.index("TenantID")] = tenant.get("id")
        row[ICDN_HEADERS.index("Tenant")] = tenant.get("name")
        row[ICDN_HEADERS.index("Description")] = it.get("description")
        row[ICDN_HEADERS.index("Amount")] = _flt(it.get("amount"))
        row[ICDN_HEADERS.index("Matched amount")] = _flt(it.get("matched_amount"))
        row[ICDN_HEADERS.index("RefNo")] = it.get("id")
        row[ICDN_HEADERS.index("DepositReference")] = it.get("deposit_id")
        rows.append(row)
    return rows


def normalize_active_beneficiaries(items: list[dict]) -> list[list]:
    """payprop_get_beneficiaries items -> Active Beneficiaries tab rows.

    ASSUMPTION (unverified against a real report run yet): "active
    beneficiary" = is_owner true with at least one property assignment;
    BenStatus is derived from is_active_owner since the API has no direct
    status string. notify_email/notify_sms come through as booleans and are
    converted to the template's Y/N convention. Commission/Amount/
    PropertyAmount aren't in this API response, so those columns are left
    blank (cosmetic only -- no Summary formula reads them).
    """
    H = ACTIVE_BENEFICIARIES_HEADERS
    rows = []
    for b in items:
        if not b.get("is_owner"):
            continue
        props = b.get("properties") or []
        if not props:
            continue
        addr = b.get("billing_address") or {}
        name = b.get("business_name") or f"{b.get('first_name', '')} {b.get('last_name', '')}".strip()
        ben_status = "Active" if b.get("is_active_owner") else "Inactive"
        for p in props:
            row = [None] * len(H)
            row[H.index("Name")] = name
            row[H.index("EmailAddress")] = b.get("email_address")
            row[H.index("Mobile")] = b.get("mobile_number")
            row[H.index("Address1")] = addr.get("first_line")
            row[H.index("Address2")] = addr.get("second_line")
            row[H.index("Address3")] = addr.get("third_line")
            row[H.index("City")] = addr.get("city")
            row[H.index("PostalCode")] = addr.get("postal_code")
            row[H.index("Province")] = addr.get("state")
            row[H.index("Country")] = addr.get("country_code")
            row[H.index("PropertyID")] = p.get("id")
            row[H.index("PropertyName")] = p.get("property_name")
            row[H.index("AgreementID")] = p.get("id")
            row[H.index("BenStatus")] = ben_status
            row[H.index("NotifyEmail")] = _bool_to_yn(b.get("notify_email"))
            row[H.index("NotifySMS")] = _bool_to_yn(b.get("notify_sms"))
            row[H.index("Agent")] = p.get("responsible_agent")
            rows.append(row)
    return rows


def normalize_arrears_report(arrears_items: list[dict]) -> list[list]:
    """The Payprop sync pipeline's scripts/report-arrears.mjs output (the
    "arrears" array of data/tenant-arrears-report.json) -> Arrears tab rows.

    This source has no aging buckets (0-30/31-60/etc.) -- it's a snapshot of
    current total balance per tenant, not an aged breakdown -- so those
    columns are left blank/0 and only ID/TenantName/Property/Total are
    populated. `balance` in this source is negative for money owed (see the
    Payprop repo's README); the template's convention is a positive "Total
    arrears" figure, so the sign is flipped here.
    """
    H = ARREARS_HEADERS
    rows = []
    for it in arrears_items:
        row = [None] * len(H)
        row[H.index("ID")] = it.get("tenant_payprop_id")
        row[H.index("TenantName")] = it.get("tenant_name")
        row[H.index("Property")] = it.get("property_name")
        row[H.index("Total")] = abs(_flt(it.get("balance"), 0.0))
        rows.append(row)
    return rows


_DATE_FORMATS = ("%Y-%m-%d", "%d/%m/%Y", "%Y-%m-%d %H:%M:%S", "%d %B %Y", "%d-%b-%Y")


def _looks_like_leading_zero_id(s: str) -> bool:
    # "0210000000" (phone), "007..." (an ID/postal code) -- these must stay
    # strings, since int()/float() would silently drop the leading zero.
    bare = s[1:] if s[:1] == "-" else s
    return len(bare) > 1 and bare[0] == "0" and bare[1] != "."


def _coerce(v: str):
    if v is None or v == "":
        return None
    s = v.strip()
    if _looks_like_leading_zero_id(s):
        return s
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s.replace(",", ""))
    except ValueError:
        pass
    for fmt in _DATE_FORMATS:
        try:
            return datetime.datetime.strptime(s, fmt)
        except ValueError:
            continue
    return v


def load_csv_rows(path: str, headers: list[str]) -> list[list]:
    """Reads a PayProp CSV export and returns rows positionally matched to
    `headers`. Values are matched by column POSITION, not by header text --
    some PayProp exports (e.g. All Payments) legitimately repeat a column
    name (two "VAT" columns), so name-based lookup would silently drop data.
    Extra/missing trailing columns are padded/truncated to len(headers).
    """
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        file_header = next(reader, [])
        if [h.strip().lower() for h in file_header[:len(headers)]] != [h.lower() for h in headers[:len(file_header)]]:
            print(f"WARNING: {path} header row doesn't look like the expected PayProp export "
                  f"for this tab -- proceeding positionally anyway. Got: {file_header[:5]}...")
        rows = []
        for raw in reader:
            if not any(cell.strip() for cell in raw):
                continue
            vals = [_coerce(v) for v in raw]
            if len(vals) < len(headers):
                vals += [None] * (len(headers) - len(vals))
            rows.append(vals[:len(headers)])
    return rows
