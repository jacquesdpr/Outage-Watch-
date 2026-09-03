#!/usr/bin/env python3
"""
Orchestrates one report run: merges the live-pulled tabs (ICDN, Active
Beneficiaries -- dumped to JSON by the calling chat turn, since only Claude
can call the PayProp MCP tools) with the manually-exported CSVs for the tabs
PayProp doesn't expose in bulk, then writes the single output workbook.

Usage:
    python generate_report.py \
        --icdn-json data/icdn.json \
        --beneficiaries-json data/beneficiaries.json \
        --all-tenants-csv uploads/all_tenants.csv \
        --arrears-csv uploads/arrears.csv \
        --beneficiary-balances-csv uploads/beneficiary_balances.csv \
        --expired-contracts-csv uploads/expired_contracts.csv \
        --all-payments-csv uploads/all_payments.csv \
        --output report.xlsx \
        --client "Invitation Homes Management (Pty) Ltd" \
        --ref 58 \
        --period "1-31 August 2026"

Any --*-csv flag may be omitted; the matching tab/metrics are then marked
"N/A - awaiting API access" instead of guessing.
"""
from __future__ import annotations

import argparse
import datetime
import json
import sys

from build_report import (
    build_workbook, ALL_TENANTS_HEADERS, ARREARS_HEADERS,
    EXPIRED_CONTRACTS_HEADERS, BENEFICIARY_BALANCES_HEADERS,
    ALL_PAYMENTS_HEADERS,
)
from payprop_normalize import (
    normalize_icdn, normalize_active_beneficiaries, load_csv_rows,
)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--icdn-json", required=True)
    p.add_argument("--beneficiaries-json", required=True)
    p.add_argument("--all-tenants-csv", required=True)
    p.add_argument("--arrears-csv", required=True)
    p.add_argument("--expired-contracts-csv", required=True)
    p.add_argument("--beneficiary-balances-csv")
    p.add_argument("--all-payments-csv")
    p.add_argument("--output", required=True)
    p.add_argument("--client", required=True)
    p.add_argument("--ref", required=True)
    p.add_argument("--period", required=True)
    p.add_argument("--report-date", help="YYYY-MM-DD, defaults to today")
    args = p.parse_args()

    report_date = (datetime.date.fromisoformat(args.report_date)
                   if args.report_date else datetime.date.today())

    with open(args.icdn_json) as f:
        icdn_items = json.load(f)
    with open(args.beneficiaries_json) as f:
        ben_items = json.load(f)

    icdn_rows = normalize_icdn(icdn_items)
    active_ben_rows = normalize_active_beneficiaries(ben_items)

    all_tenants_rows = load_csv_rows(args.all_tenants_csv, ALL_TENANTS_HEADERS)
    arrears_rows = load_csv_rows(args.arrears_csv, ARREARS_HEADERS)
    expired_rows = load_csv_rows(args.expired_contracts_csv, EXPIRED_CONTRACTS_HEADERS)
    ben_bal_rows = (load_csv_rows(args.beneficiary_balances_csv, BENEFICIARY_BALANCES_HEADERS)
                    if args.beneficiary_balances_csv else None)
    all_pay_rows = (load_csv_rows(args.all_payments_csv, ALL_PAYMENTS_HEADERS)
                    if args.all_payments_csv else None)

    build_workbook(
        args.output, args.client, args.ref, report_date, args.period,
        all_tenants_rows, arrears_rows, expired_rows, icdn_rows, active_ben_rows,
        beneficiary_balances_rows=ben_bal_rows, all_payments_rows=all_pay_rows,
    )
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    sys.exit(main())
