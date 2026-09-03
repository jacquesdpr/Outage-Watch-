#!/usr/bin/env python3
"""
Builds the "Portfolio Health Check" report for Invitation Homes Management (Pty) Ltd.

This module only turns already-normalized rows (plain lists of values, in the
same column order PayProp's own CSV exports use) into the formatted .xlsx.
Every Summary metric is written as a real Excel formula (so the workbook
keeps working if someone edits the data tabs by hand later) *and* with its
correct cached value pre-computed in Python, because this sandbox's
LibreOffice cannot reliably recalculate on save -- see NOTES.md. It does not
talk to PayProp itself -- see fetch_data.py for that half.

Usage (library):
    from build_report import build_workbook
    build_workbook(output_path, client_name, client_ref, report_date, period_label,
                    all_tenants_rows, arrears_rows, expired_contracts_rows,
                    icdn_rows, active_beneficiaries_rows,
                    beneficiary_balances_rows=None, all_payments_rows=None)

Each *_rows argument is a list of rows; each row is a list/tuple of values in
exactly the column order given by the matching *_HEADERS constant below.
"""
from __future__ import annotations

import datetime
import xlsxwriter

# ---------------------------------------------------------------------------
# Column headers, in the exact order the original CSM template uses (and
# that PayProp's own CSV exports use). Rows passed to build_workbook must be
# in this same order. Note some PayProp exports legitimately repeat a header
# name (e.g. All Payments has two "VAT" columns) -- that's why rows are
# positional lists, not dicts.
# ---------------------------------------------------------------------------

ALL_TENANTS_HEADERS = [
    "No", "PayorName", "PropertyID", "PropertyName", "DepositID", "Amount",
    "Currency", "PayDay", "AccountType", "Balance", "ContractID",
    "EmailAddress", "Mobile", "ResponsibleAgent", "ResponsibleUser",
    "Address1", "Address2", "Address3", "City", "Province", "PostalCode",
    "Country", "Phone", "Fax", "PayerStatus", "StartDate", "EndDate",
    "NotifyEmail", "NotifySMS", "DepBalance", "LastInvoice", "LastPayment",
    "LastReminder", "CustomerRefTenant", "CustomerRefProperty", "Tags",
    "Dep/Rent Ratio",
]  # A..AK

ARREARS_HEADERS = [
    "ID", "TenantName", "Property", "Agent", "Phone", "Cellphone", "E-mail",
    "0 - 30", "31 - 60", "61 - 90", "90 - 120", "> 120", "Total",
]  # A..M

BENEFICIARY_BALANCES_HEADERS = [
    "Beneficiary", "Property", "Agent", "Category", "Description", "Date",
    "Amount",
]  # A..G

EXPIRED_CONTRACTS_HEADERS = [
    "No", "PayorName", "PropertyID", "PropertyName", "DepositID", "Amount",
    "Currency", "PayDay", "AccountType", "Balance", "ContractID",
    "EmailAddress", "Mobile", "ResponsibleAgent", "Address1", "Address2",
    "Address3", "City", "Province", "PostalCode", "Country", "Phone", "Fax",
    "PayerStatus", "StartDate", "EndDate", "NotifyEmail", "NotifySMS",
    "DepBalance", "LastInvoice", "LastPayment", "LastReminder",
    "CustomerRefTenant", "CustomerRefProperty", "ResponsibleUser", "Tags",
]  # A..AJ

ICDN_HEADERS = [
    "PropertyID", "Property", "Agent", "Date", "Type", "InvoiceType",
    "TenantID", "Tenant", "Description", "Amount", "VAT", "Matched amount",
    "RefNo", "DepositReference", "CustomerRefTenant", "CustomerRefProperty",
]  # A..P

ACTIVE_BENEFICIARIES_HEADERS = [
    "No", "Name", "EmailAddress", "Mobile", "Phone", "Fax", "Address1",
    "Address2", "Address3", "City", "PostalCode", "Province", "Country",
    "PropertyID", "PropertyName", "BenType", "Commission", "Amount",
    "PropertyAmount", "AgreementID", "BenStatus", "NotifyEmail",
    "NotifySMS", "CustomerRefBeneficiary", "CustomerRefProperty", "Agent",
    "Tags",
]  # A..AA

ALL_PAYMENTS_HEADERS = [
    "PaymentRecordID", "ID", "PropertyID", "Property", "BankStatementDate",
    "ReconDate", "PayorID", "PayorName", "BeforeSplitAmount", "PaidAmount",
    "FormattedPaidAmount", "VAT", "PaymentType", "CurrencyBeforeSplitAmount",
    "TransactionFee", "ServiceFee", "Status", "Inc VAT", "VAT",
    "Excl VAT", "CurrencyAfterSplitAmount", "BenType", "BenID",
    "BeneficiaryName", "DueDate", "TransferredDate", "RemitID",
    "RemitStatus", "DiffAmount", "TransferredDateMonth", "BalanceAmount",
    "AdjustmentAmount", "AdjustedAmount", "BenDescription", "BenReference",
    "ResponsibleAgent", "BeneficiaryType", "DepRef", "PartOfAmount",
    "CustomerRefProperty", "CustomerRefTenant", "CustomerRefBeneficiary",
    "CustomerRefInvoice", "BankStatementID",
]  # A..AR


def col(headers, name):
    """0-based index of a column by header name (first match)."""
    return headers.index(name)


def _blank(v):
    return v is None or v == ""


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def _eq(v, target):
    return isinstance(v, str) and v.strip().lower() == target.lower()


# ---------------------------------------------------------------------------
# Metric computation -- one function per Summary metric, each mirroring the
# exact Excel formula from the original CSM template (kept in a comment).
# ---------------------------------------------------------------------------

def compute_metrics(all_tenants, arrears, expired_contracts, icdn,
                     active_beneficiaries, beneficiary_balances,
                     all_payments, report_date):
    AT = ALL_TENANTS_HEADERS
    y, aa, j, ac, ab, ad, ak = (col(AT, n) for n in
        ("PayerStatus", "EndDate", "Balance", "NotifySMS", "NotifyEmail", "DepBalance", "Dep/Rent Ratio"))

    m = {}

    # =COUNTIF('All Tenants'!Y:Y,"Active")
    m["active_tenants"] = sum(1 for r in all_tenants if _eq(r[y], "Active"))
    # =COUNTIF('All Tenants'!Y:Y,"Inactive")
    m["inactive_tenants"] = sum(1 for r in all_tenants if _eq(r[y], "Inactive"))
    # =COUNTIFS(Y:Y,"Active",AA:AA,"")
    m["no_end_date_active"] = sum(1 for r in all_tenants if _eq(r[y], "Active") and _blank(r[aa]))
    # =COUNTIFS(Y:Y,"Active",J:J,">0")
    m["active_credit_balance"] = sum(1 for r in all_tenants if _eq(r[y], "Active") and _num(r[j]) > 0)
    # =COUNTA(Arrears!B:B) -- counts the header row too, exactly like the original template
    AR = ARREARS_HEADERS
    tenant_name_col = col(AR, "TenantName")
    m["tenants_in_arrears"] = 1 + sum(1 for r in arrears if not _blank(r[tenant_name_col]))
    # =SUM(Arrears!M:M)
    total_col = col(AR, "Total")
    m["total_arrears_value"] = sum(_num(r[total_col]) for r in arrears)
    # =COUNTIFS(Y:Y,"Active",AC:AC,"Y")
    m["sms_on"] = sum(1 for r in all_tenants if _eq(r[y], "Active") and _eq(r[ac], "Y"))
    # =COUNTIFS(Y:Y,"Active",AC:AC,"N")
    m["sms_off"] = sum(1 for r in all_tenants if _eq(r[y], "Active") and _eq(r[ac], "N"))
    # =COUNTIFS(Y:Y,"Active",AB:AB,"N")
    m["email_off"] = sum(1 for r in all_tenants if _eq(r[y], "Active") and _eq(r[ab], "N"))
    # =COUNTIFS(AB:AB,"N",AC:AC,"N",Y:Y,"Active")
    m["no_notifications"] = sum(1 for r in all_tenants if _eq(r[ab], "N") and _eq(r[ac], "N") and _eq(r[y], "Active"))
    # =COUNTIFS('Active Beneficiaries'!U:U,"Active",V:V,"N",W:W,"N")
    AB_H = ACTIVE_BENEFICIARIES_HEADERS
    bstat, bemail, bsms = (col(AB_H, n) for n in ("BenStatus", "NotifyEmail", "NotifySMS"))
    m["ben_no_notifications"] = sum(
        1 for r in active_beneficiaries if _eq(r[bstat], "Active") and _eq(r[bemail], "N") and _eq(r[bsms], "N"))
    # =COUNTIFS(Y:Y,"Active",AD:AD,0)
    m["active_no_deposit"] = sum(1 for r in all_tenants if _eq(r[y], "Active") and _num(r[ad]) == 0)
    # =COUNTIFS(Y:Y,"Active",AK:AK,"<1",AK:AK,"<>")
    m["active_deposit_under_100pct"] = sum(
        1 for r in all_tenants if _eq(r[y], "Active") and not _blank(r[ak]) and _num(r[ak]) < 1)
    # Original template: =COUNTIFS(Y:Y,"<>Active",Y:Y,"<>",AD:AD,"<>0")-1, where the
    # "-1" offsets the header row spuriously matching all three conditions over a
    # full-column reference. We count data rows only, so no offset is needed.
    m["inactive_with_deposit"] = sum(
        1 for r in all_tenants if not _eq(r[y], "Active") and not _blank(r[y]) and _num(r[ad]) != 0)
    # =SUMIFS(AD:AD,Y:Y,"Active")
    m["total_deposit_active"] = sum(_num(r[ad]) for r in all_tenants if _eq(r[y], "Active"))
    # =SUMIFS(AD:AD,Y:Y,"Inactive")
    m["total_deposit_inactive"] = sum(_num(r[ad]) for r in all_tenants if _eq(r[y], "Inactive"))

    IC = ICDN_HEADERS
    itype = col(IC, "Type")
    # =COUNTIF(ICDN!E:E,"Invoice")
    m["invoices"] = sum(1 for r in icdn if _eq(r[itype], "Invoice"))
    # =COUNTIF(ICDN!E:E,"Credit Note")
    m["credit_notes"] = sum(1 for r in icdn if _eq(r[itype], "Credit Note"))
    # =COUNTIF(ICDN!E:E,"Debit Note")
    m["debit_notes"] = sum(1 for r in icdn if _eq(r[itype], "Debit Note"))
    # =G17/G16
    m["invoice_credit_ratio"] = (m["credit_notes"] / m["invoices"]) if m["invoices"] else 0.0

    EC = EXPIRED_CONTRACTS_HEADERS
    ebal, edep = col(EC, "Balance"), col(EC, "DepBalance")
    # =COUNTIFS('Expired Contracts'!J:J,"0",AC:AC,"0")
    m["expired_deletable"] = sum(1 for r in expired_contracts if _num(r[ebal]) == 0 and _num(r[edep]) == 0)

    if beneficiary_balances is not None:
        BB = BENEFICIARY_BALANCES_HEADERS
        bdate = col(BB, "Date")
        cutoff = report_date - datetime.timedelta(days=90)

        def _as_date(v):
            if isinstance(v, datetime.datetime):
                return v.date()
            if isinstance(v, datetime.date):
                return v
            return None

        # =COUNTIF('Beneficiary Balances'!F:F,"<"&TODAY()-90)
        m["payment_instructions_over_90d"] = sum(
            1 for r in beneficiary_balances
            if _as_date(r[bdate]) is not None and _as_date(r[bdate]) < cutoff)
    else:
        m["payment_instructions_over_90d"] = None

    if all_payments is not None:
        AP = ALL_PAYMENTS_HEADERS
        inc_vat = col(AP, "Inc VAT")
        bentype = col(AP, "BenType")
        ben_kind = col(AP, "BeneficiaryType")
        # =SUMIFS('All Payments'!R:R,V:V,"C",AK:AK,"Commission")
        m["total_commission"] = sum(
            _num(r[inc_vat]) for r in all_payments if _eq(r[bentype], "C") and _eq(r[ben_kind], "Commission"))
        # =SUMIFS('All Payments'!R:R,V:V,"C")
        m["total_all_categories"] = sum(_num(r[inc_vat]) for r in all_payments if _eq(r[bentype], "C"))
    else:
        m["total_commission"] = None
        m["total_all_categories"] = None

    return m


# ---------------------------------------------------------------------------
# Formatting constants matching the original CSM template.
# ---------------------------------------------------------------------------

CURRENCY_FMT = '"R"#,##0.00'
DATE_FMT = "dd mmmm yyyy"
PCT_FMT = "0.0%"


def build_workbook(
    output_path: str,
    client_name: str,
    client_ref: str,
    report_date: datetime.date,
    period_label: str,
    all_tenants_rows,
    arrears_rows,
    expired_contracts_rows,
    icdn_rows,
    active_beneficiaries_rows,
    beneficiary_balances_rows=None,
    all_payments_rows=None,
):
    """Writes the full Health Check workbook to output_path.

    beneficiary_balances_rows / all_payments_rows may be None when PayProp's
    API doesn't expose that data yet -- the affected tabs and Summary metrics
    are then clearly marked unavailable rather than silently showing zero.
    """
    m = compute_metrics(
        all_tenants_rows, arrears_rows, expired_contracts_rows, icdn_rows,
        active_beneficiaries_rows, beneficiary_balances_rows, all_payments_rows,
        report_date,
    )

    wb = xlsxwriter.Workbook(output_path, {"default_date_format": "yyyy-mm-dd"})

    f_title = wb.add_format({"font_name": "Segoe UI", "font_size": 48})
    f_subtitle = wb.add_format({"font_name": "Segoe UI", "font_size": 24})
    f_meta = wb.add_format({"font_name": "Calibri", "font_size": 18})
    f_meta_r = wb.add_format({"font_name": "Calibri", "font_size": 18, "align": "right"})
    f_section = wb.add_format({"font_name": "Calibri", "font_size": 18, "bold": True})
    f_label = wb.add_format({"font_name": "Segoe UI", "font_size": 18})
    f_value = wb.add_format({"font_name": "Segoe UI", "font_size": 18, "align": "center", "bg_color": "#F2F2F2"})
    f_value_cur = wb.add_format({"font_name": "Segoe UI", "font_size": 18, "align": "center", "bg_color": "#F2F2F2", "num_format": CURRENCY_FMT})
    f_value_pct = wb.add_format({"font_name": "Segoe UI", "font_size": 18, "align": "center", "bg_color": "#F2F2F2", "num_format": PCT_FMT})
    f_value_na = wb.add_format({"font_name": "Segoe UI", "font_size": 18, "align": "center", "bg_color": "#FFF2CC"})
    f_date = wb.add_format({"font_name": "Calibri", "font_size": 18, "align": "right", "num_format": DATE_FMT})
    f_header = wb.add_format({"font_name": "Calibri", "bold": True, "bg_color": "#D9D9D9", "border": 1})
    f_rec_ref = wb.add_format({"font_name": "Calibri", "font_size": 14, "align": "center", "valign": "top"})
    f_rec_text = wb.add_format({"font_name": "Calibri", "font_size": 14, "text_wrap": True, "valign": "top"})
    f_note = wb.add_format({"font_name": "Calibri", "font_size": 11, "italic": True, "bg_color": "#FFF2CC"})

    def data_sheet(name, headers, rows):
        ws = wb.add_worksheet(name)
        for i, h in enumerate(headers):
            ws.write(0, i, h, f_header)
        for r, record in enumerate(rows, start=1):
            for i, v in enumerate(record):
                if i >= len(headers):
                    break
                ws.write(r, i, v)
        ws.set_column(0, len(headers) - 1, 16)
        ws.freeze_panes(1, 0)
        return ws

    data_sheet("All Tenants", ALL_TENANTS_HEADERS, all_tenants_rows)
    data_sheet("Arrears", ARREARS_HEADERS, arrears_rows)
    ws_bb = data_sheet("Beneficiary Balances", BENEFICIARY_BALANCES_HEADERS, beneficiary_balances_rows or [])
    data_sheet("Expired Contracts", EXPIRED_CONTRACTS_HEADERS, expired_contracts_rows)
    data_sheet("ICDN", ICDN_HEADERS, icdn_rows)
    data_sheet("Active Beneficiaries", ACTIVE_BENEFICIARIES_HEADERS, active_beneficiaries_rows)
    ws_ap = data_sheet("All Payments", ALL_PAYMENTS_HEADERS, all_payments_rows or [])

    if beneficiary_balances_rows is None:
        ws_bb.write(0, 0, "Data not available via PayProp API yet", f_note)
    if all_payments_rows is None:
        ws_ap.write(0, 0, "Data not available via PayProp API yet", f_note)

    n_at = len(all_tenants_rows) + 1
    n_ar = len(arrears_rows) + 1
    n_ic = len(icdn_rows) + 1
    n_ec = len(expired_contracts_rows) + 1
    n_ab = len(active_beneficiaries_rows) + 1
    n_bb = len(beneficiary_balances_rows or []) + 1
    n_ap = len(all_payments_rows or []) + 1

    ws = wb.add_worksheet("Summary")
    wb.worksheets_objs.insert(0, wb.worksheets_objs.pop())  # move Summary first

    ws.set_column("A:A", 2.7)
    ws.set_column("B:B", 1.5)
    ws.set_column("C:C", 63.5)
    ws.set_column("D:D", 21.7)
    ws.set_column("E:E", 3)
    ws.set_column("F:F", 61.3)
    ws.set_column("G:G", 27.8)
    ws.set_column("K:K", 5.7)
    ws.set_column("M:M", 60)

    ws.write("C3", "        Portfolio Health Check ", f_title)
    ws.set_row(2, 67)
    ws.write("C5", client_name, f_subtitle)
    ws.write("C6", f"Ref : {client_ref}", f_meta)
    ws.write("F5", "Report Date :", f_meta_r)
    ws.write_datetime("G5", report_date, f_date)
    ws.write("F6", "Data Extracted for Period : ", f_meta_r)
    ws.write("G6", period_label, f_meta_r)

    ws.write("C8", "Tenants", f_section)
    ws.write("F8", "Deposits", f_section)

    def metric(cell_label, cell_value, label, formula, value, fmt=f_value):
        ws.write(cell_label, label, f_label)
        ws.write_formula(cell_value, formula, fmt, value)

    metric("C9", "D9", "1. Total Active tenants ", f"=COUNTIF('All Tenants'!Y2:Y{n_at},\"Active\")", m["active_tenants"])
    metric("C10", "D10", "2. Total Inactive tenants", f"=COUNTIF('All Tenants'!Y2:Y{n_at},\"Inactive\")", m["inactive_tenants"])
    metric("C11", "D11", "3. No End Date on Active tenant invoices",
           f"=COUNTIFS('All Tenants'!Y2:Y{n_at},\"Active\",'All Tenants'!AA2:AA{n_at},\"\")", m["no_end_date_active"])
    metric("C12", "D12", "4. Active Tenants with a credit balance",
           f"=COUNTIFS('All Tenants'!Y2:Y{n_at},\"Active\",'All Tenants'!J2:J{n_at},\">0\")", m["active_credit_balance"])
    metric("C13", "D13", "5. Total Tenants in arrears", f"=COUNTA(Arrears!B1:B{n_ar})", m["tenants_in_arrears"])
    metric("C14", "D14", "6. Total Arrears value", f"=SUM(Arrears!M2:M{n_ar})", m["total_arrears_value"], f_value_cur)

    ws.write("C16", "Notifications", f_section)
    metric("C17", "D17", "7. SMS Notifications ON for Active Tenants",
           f"=COUNTIFS('All Tenants'!Y2:Y{n_at},\"Active\",'All Tenants'!AC2:AC{n_at},\"Y\")", m["sms_on"])
    metric("C18", "D18", "8. SMS Notifications OFF for Active Tenants",
           f"=COUNTIFS('All Tenants'!Y2:Y{n_at},\"Active\",'All Tenants'!AC2:AC{n_at},\"N\")", m["sms_off"])
    metric("C19", "D19", "9. Email Notifications OFF for Active Tenants",
           f"=COUNTIFS('All Tenants'!Y2:Y{n_at},\"Active\",'All Tenants'!AB2:AB{n_at},\"N\")", m["email_off"])
    metric("C20", "D20", "10. Active Tenants with NO Notifications ",
           f"=COUNTIFS('All Tenants'!AB2:AB{n_at},\"N\",'All Tenants'!AC2:AC{n_at},\"N\",'All Tenants'!Y2:Y{n_at},\"Active\")", m["no_notifications"])
    metric("C21", "D21", "11. Active Beneficiaries with NO Notifications",
           f"=COUNTIFS('Active Beneficiaries'!U2:U{n_ab},\"Active\",'Active Beneficiaries'!V2:V{n_ab},\"N\",'Active Beneficiaries'!W2:W{n_ab},\"N\")",
           m["ben_no_notifications"])

    metric("F9", "G9", "12. Active tenants NO Deposits",
           f"=COUNTIFS('All Tenants'!Y2:Y{n_at},\"Active\",'All Tenants'!AD2:AD{n_at},0)", m["active_no_deposit"])
    metric("F10", "G10", "13. Active tenants <100% Deposit",
           f"=COUNTIFS('All Tenants'!Y2:Y{n_at},\"Active\",'All Tenants'!AK2:AK{n_at},\"<1\",'All Tenants'!AK2:AK{n_at},\"<>\")",
           m["active_deposit_under_100pct"])
    metric("F11", "G11", "14. Inactive/Archived tenants with Deposits ",
           f"=COUNTIFS('All Tenants'!Y2:Y{n_at},\"<>Active\",'All Tenants'!Y2:Y{n_at},\"<>\",'All Tenants'!AD2:AD{n_at},\"<>0\")",
           m["inactive_with_deposit"])
    metric("F12", "G12", "15. Total Deposit : Active Tenants",
           f"=SUMIFS('All Tenants'!AD2:AD{n_at},'All Tenants'!Y2:Y{n_at},\"Active\")", m["total_deposit_active"], f_value_cur)
    metric("F13", "G13", "16. Total Deposit : Inactive Tenants",
           f"=SUMIFS('All Tenants'!AD2:AD{n_at},'All Tenants'!Y2:Y{n_at},\"Inactive\")", m["total_deposit_inactive"], f_value_cur)

    ws.write("F15", "Invoices & Credit Notes", f_section)
    metric("F16", "G16", "18. No. Invoices in Previous Month", f"=COUNTIF(ICDN!E2:E{n_ic},\"Invoice\")", m["invoices"])
    metric("F17", "G17", "19. No. Credit Notes in Previous Month", f"=COUNTIF(ICDN!E2:E{n_ic},\"Credit Note\")", m["credit_notes"])
    metric("F18", "G18", "20. No. Debit Notes in Previous Month", f"=COUNTIF(ICDN!E2:E{n_ic},\"Debit Note\")", m["debit_notes"])
    metric("F19", "G19", "21. Ratio of Invoices to Credit Notes", "=IFERROR(G17/G16,0)", m["invoice_credit_ratio"], f_value_pct)
    metric("F20", "G20", "22. Expired Invoices that can be deleted",
           f"=COUNTIFS('Expired Contracts'!J2:J{n_ec},0,'Expired Contracts'!AC2:AC{n_ec},0)", m["expired_deletable"])

    ws.write("F22", "Payments", f_section)
    if m["payment_instructions_over_90d"] is not None:
        metric("F23", "G23", "23. Payment Instructions older than 90 days",
               f"=COUNTIF('Beneficiary Balances'!F2:F{n_bb},\"<\"&TODAY()-90)", m["payment_instructions_over_90d"])
    else:
        ws.write("F23", "23. Payment Instructions older than 90 days", f_label)
        ws.write("G23", "N/A - awaiting API access", f_value_na)

    if m["total_commission"] is not None:
        metric("F24", "G24", "24. Total Commission Category Only",
               f"=SUMIFS('All Payments'!R2:R{n_ap},'All Payments'!V2:V{n_ap},\"C\",'All Payments'!AK2:AK{n_ap},\"Commission\")",
               m["total_commission"], f_value_cur)
        metric("F25", "G25", "25. Total All Categories Incl Commission",
               f"=SUMIFS('All Payments'!R2:R{n_ap},'All Payments'!V2:V{n_ap},\"C\")",
               m["total_all_categories"], f_value_cur)
    else:
        for cell_label, label in (("F24", "24. Total Commission Category Only"),
                                   ("F25", "25. Total All Categories Incl Commission")):
            ws.write(cell_label, label, f_label)
        ws.write("G24", "N/A - awaiting API access", f_value_na)
        ws.write("G25", "N/A - awaiting API access", f_value_na)

    # --- Recommendations panel ----------------------------------------------
    # Only mechanically-derivable flags are auto-populated (a direct
    # restatement of a metric that has crossed a threshold). Findings that
    # need human judgement about *why* (e.g. "these are storerooms", "this
    # beneficiary is an admin account") are intentionally left for the
    # reviewer to fill in -- fabricating that context would misrepresent the
    # data as investigated when it hasn't been.
    ws.write("K4", "Ref", f_header)
    ws.write("M4", "Recommendations", f_header)

    recs = []
    if m["tenants_in_arrears"] > 1:
        recs.append((5, f"{m['tenants_in_arrears'] - 1} tenant(s) in arrears totalling "
                         f"R{m['total_arrears_value']:,.2f} -- target 120+ day arrears with a "
                         f"Letter of Demand and discuss cancellation with the Landlord."))
    if m["sms_off"] > 0:
        recs.append((7, f"{m['sms_off']} active tenant(s) have SMS notifications OFF -- "
                         f"confirm this is intentional, or re-enable to reduce missed-payment risk."))
    if m["email_off"] > 0:
        recs.append((9, f"{m['email_off']} active tenant(s) have email notifications OFF -- "
                         f"validate this is intentional."))
    if m["no_notifications"] > 0:
        recs.append((10, f"{m['no_notifications']} active tenant(s) have NO notifications at all "
                          f"(SMS or email) -- validate this is intentional."))
    if m["active_deposit_under_100pct"] > 0:
        recs.append((13, f"{m['active_deposit_under_100pct']} active tenant(s) have a deposit "
                          f"below 100% of rent -- review and top up where required."))
    if m["inactive_with_deposit"] > 0:
        recs.append((14, f"{m['inactive_with_deposit']} inactive/archived tenant(s) still hold a "
                          f"deposit balance -- review for refund or reallocation."))
    if m["active_no_deposit"] > 0:
        recs.append((12, f"{m['active_no_deposit']} active tenant(s) have NO deposit on record -- "
                          f"confirm exemption (e.g. storeroom/garage) or collect deposit."))
    if m["expired_deletable"] > 0:
        recs.append((22, f"{m['expired_deletable']} expired contract(s) flagged with zero balance "
                          f"-- review and archive/delete as appropriate."))

    row = 4
    for ref, text in recs:
        ws.write(row, 10, ref, f_rec_ref)     # K
        ws.write(row, 12, text, f_rec_text)   # M
        ws.set_row(row, 34)
        row += 2

    ws.write(row, 10, "--", f_rec_ref)
    ws.write(row, 12,
             "Needs manual review (context PayProp data can't supply): beneficiary-with-no-"
             "notification exemptions, storeroom/garage deposit exemptions, VAT-indicator "
             "checks on service income.", f_rec_text)
    ws.set_row(row, 48)

    wb.close()
    return output_path
