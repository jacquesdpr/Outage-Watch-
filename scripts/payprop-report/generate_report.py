#!/usr/bin/env python3
"""
Orchestrates one report run:
  - ICDN: live PayProp MCP calls, dumped to JSON by the calling chat turn
    (only Claude can call MCP tools, this script can't), then normalized
    here.
  - Active Beneficiaries: prefer the sync pipeline's data/landlords.json
    (already reconciled, correct beneficiary_type/status fields); falls
    back to a live payprop_get_beneficiaries JSON dump if the pipeline
    clone isn't available (less reliable -- see payprop_normalize.py).
  - Arrears: prefer a fresh data/tenant-arrears-report.json from the
    jacquesdpr/payprop sync pipeline's arrears-report GitHub Action; falls
    back to a manually exported Arrears CSV if that's not available.
  - All Tenants: always a manually exported CSV -- the sync pipeline's
    master tenants.json only covers ~700 current/recent tenants, nowhere
    near the full active+inactive history this tab needs (see README.md).
  - Expired Contracts, Beneficiary Balances, All Payments: manually
    exported CSV, optional -- omitted tabs/metrics are marked
    "N/A - awaiting API access" rather than guessed.

Usage:
    python generate_report.py \
        --icdn-json data/icdn.json \
        --landlords-master-json /home/user/payprop/data/landlords.json \
        --all-tenants-csv uploads/all_tenants.csv \
        --arrears-report-json /home/user/payprop/data/tenant-arrears-report.json \
        --output report.xlsx \
        --client "Invitation Homes Management (Pty) Ltd" \
        --ref 58 \
        --period "1-31 August 2026"
"""
from __future__ import annotations

import argparse
import datetime
import json
import sys

from build_report import (
    build_workbook, ARREARS_HEADERS,
    EXPIRED_CONTRACTS_HEADERS, BENEFICIARY_BALANCES_HEADERS,
    ALL_PAYMENTS_HEADERS,
)
from payprop_normalize import (
    normalize_icdn, normalize_active_beneficiaries, normalize_landlords_master,
    normalize_arrears_report, load_csv_rows, load_all_tenants_csv,
)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--icdn-json", required=True)
    p.add_argument("--landlords-master-json", help="data/landlords.json from the sync pipeline (preferred)")
    p.add_argument("--beneficiaries-json", help="fallback raw payprop_get_beneficiaries dump")
    p.add_argument("--all-tenants-csv", required=True)
    p.add_argument("--arrears-report-json", help="data/tenant-arrears-report.json from the sync pipeline")
    p.add_argument("--arrears-csv", help="fallback if --arrears-report-json isn't available")
    p.add_argument("--expired-contracts-csv")
    p.add_argument("--beneficiary-balances-csv")
    p.add_argument("--all-payments-csv")
    p.add_argument("--output", required=True)
    p.add_argument("--client", required=True)
    p.add_argument("--ref", required=True)
    p.add_argument("--period", required=True)
    p.add_argument("--report-date", help="YYYY-MM-DD, defaults to today")
    args = p.parse_args()

    if not args.arrears_report_json and not args.arrears_csv:
        p.error("one of --arrears-report-json or --arrears-csv is required")
    if not args.landlords_master_json and not args.beneficiaries_json:
        p.error("one of --landlords-master-json or --beneficiaries-json is required")

    report_date = (datetime.date.fromisoformat(args.report_date)
                   if args.report_date else datetime.date.today())

    with open(args.icdn_json) as f:
        icdn_items = json.load(f)
    icdn_rows = normalize_icdn(icdn_items)

    if args.landlords_master_json:
        with open(args.landlords_master_json) as f:
            landlords = json.load(f)
        active_ben_rows = normalize_landlords_master(landlords["records"])
    else:
        with open(args.beneficiaries_json) as f:
            ben_items = json.load(f)
        active_ben_rows = normalize_active_beneficiaries(ben_items)

    all_tenants_rows = load_all_tenants_csv(args.all_tenants_csv)

    if args.arrears_report_json:
        with open(args.arrears_report_json) as f:
            arrears_report = json.load(f)
        arrears_rows = normalize_arrears_report(arrears_report["arrears"])
    else:
        arrears_rows = load_csv_rows(args.arrears_csv, ARREARS_HEADERS)

    expired_rows = (load_csv_rows(args.expired_contracts_csv, EXPIRED_CONTRACTS_HEADERS)
                    if args.expired_contracts_csv else None)
    ben_bal_rows = (load_csv_rows(args.beneficiary_balances_csv, BENEFICIARY_BALANCES_HEADERS)
                    if args.beneficiary_balances_csv else None)
    all_pay_rows = (load_csv_rows(args.all_payments_csv, ALL_PAYMENTS_HEADERS)
                    if args.all_payments_csv else None)

    build_workbook(
        args.output, args.client, args.ref, report_date, args.period,
        all_tenants_rows, arrears_rows, icdn_rows, active_ben_rows,
        expired_contracts_rows=expired_rows,
        beneficiary_balances_rows=ben_bal_rows, all_payments_rows=all_pay_rows,
    )
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    sys.exit(main())
