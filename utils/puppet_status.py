#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time
from urllib.parse import urljoin

from datetime import datetime

import requests


def build_query_failed() -> str:
    return 'puppet_status{state="failed",environment="production",host=~".*"}'

def build_query_report() -> str:
    return 'puppet_report{environment="production",host=~".*"}'

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Query Prometheus for failed puppet_status metrics in production."
    )
    parser.add_argument(
        "--url",
        default=os.getenv("PROMETHEUS_URL", "").strip(),
        help="Base URL for Prometheus (or set PROMETHEUS_URL).",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="HTTP timeout in seconds.",
    )
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Print raw JSON response.",
    )
    return parser.parse_args()


def query_prometheus(query_url, query):
    now = time.time()
    end = now
    start = end - 3600
    step = 60

    try:
        resp = requests.get(
            query_url,
            params={"query": query, "start": start, "end": end, "step": step},
        )
    except requests.RequestException as exc:
        print(f"Error: failed to connect to {query_url}: {exc}", file=sys.stderr)

    if resp.status_code != 200:
        print(f"Error: HTTP {resp.status_code} from {query_url}", file=sys.stderr)

    try:
        payload = resp.json()
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON response: {exc}", file=sys.stderr)

    status = payload.get("status")
    if status != "success":
        print(f"Error: query failed: {payload}", file=sys.stderr)

    return payload

def main() -> int:
    args = parse_args()
    if not args.url:
        print("Error: Prometheus base URL is required via --url or PROMETHEUS_URL.", file=sys.stderr)
        return 2

    base_url = args.url.rstrip("/") + "/"
    query_url = urljoin(base_url, "api/v1/query_range")
    query = build_query_report()

    payload = query_prometheus(query_url, query)
    results = payload.get("data", {}).get("result", [])
    if not results:
        print("No failed puppet_status metrics found.")
        return 0

    query = build_query_failed()
    payload = query_prometheus(query_url, query)
    results_failed = payload.get("data", {}).get("result", [])

    host_metrics = {}
    for timestamp, failed in zip(results, results_failed):
        metric = timestamp['metric']
        host = metric.get("host", "unknown")
        val_tim = timestamp.get("values", [])
        val_fai = failed.get("values", [])
        host_metrics[host] = set([ (datetime.fromtimestamp(float(tim[1])), fai[1]) for tim, fai in zip(val_tim, val_fai)])
        host_metrics[host] = sorted(host_metrics[host], key=lambda x: x[0])

    for host, series in host_metrics.items():
        serie = [int(value[1]) == 0  for i, value in enumerate(series)]
        print(f"host={host} serie={serie}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
