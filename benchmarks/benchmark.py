#!/usr/bin/env python3
"""
Performance benchmarks for aslan-browser.
Requires the aslan-browser app to be running.

Usage:
    python3 benchmarks/benchmark.py
"""

import os
import sys
import time
import statistics

# Add SDK to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "sdk", "python"))

from aslan_browser import AslanBrowser

SOCKET_PATH = "/tmp/aslan-browser.sock"
COMPLEX_PAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "complex_page.html")


def bench(name: str, fn, iterations: int, warmup: int = 5) -> dict:
    """Run a benchmark and return stats."""
    # Warmup
    for _ in range(warmup):
        fn()

    times = []
    for _ in range(iterations):
        start = time.perf_counter()
        fn()
        elapsed = (time.perf_counter() - start) * 1000  # ms
        times.append(elapsed)

    return {
        "name": name,
        "iterations": iterations,
        "mean_ms": statistics.mean(times),
        "median_ms": statistics.median(times),
        "p95_ms": sorted(times)[int(len(times) * 0.95)],
        "min_ms": min(times),
        "max_ms": max(times),
        "stdev_ms": statistics.stdev(times) if len(times) > 1 else 0,
    }


def main():
    print(f"Connecting to {SOCKET_PATH}...")
    browser = AslanBrowser(SOCKET_PATH)

    results = []

    # ── JS eval round-trip ───────────────────────────────────────────
    print("\n[1/5] JS eval round-trip (1000 iterations)...")
    browser.navigate("https://example.com")
    time.sleep(1)
    result = bench("JS eval (1+1)", lambda: browser.evaluate("return 1+1"), 1000)
    results.append(result)
    target_met = "✓" if result["median_ms"] < 2 else "✗"
    print(f"  median: {result['median_ms']:.2f}ms (target: <2ms {target_met})")

    # ── Screenshot latency ───────────────────────────────────────────
    print("\n[2/5] Screenshot latency (100 iterations)...")
    result = bench("Screenshot (1440w, q70)", lambda: browser.screenshot(quality=70, width=1440), 100)
    results.append(result)
    target_met = "✓" if result["median_ms"] < 30 else "✗"
    print(f"  median: {result['median_ms']:.2f}ms (target: <30ms {target_met})")

    # ── Screenshot small ─────────────────────────────────────────────
    print("\n[3/5] Screenshot small (100 iterations)...")
    result = bench("Screenshot (800w, q50)", lambda: browser.screenshot(quality=50, width=800), 100)
    results.append(result)
    print(f"  median: {result['median_ms']:.2f}ms")

    # ── A11y tree on simple page ─────────────────────────────────────
    print("\n[4/5] A11y tree - simple page (100 iterations)...")
    result = bench("A11y tree (example.com)", lambda: browser.get_accessibility_tree(), 100)
    results.append(result)
    target_met = "✓" if result["median_ms"] < 50 else "✗"
    print(f"  median: {result['median_ms']:.2f}ms (target: <50ms {target_met})")

    # ── A11y tree on complex page ────────────────────────────────────
    print("\n[5/5] A11y tree - complex page (100 iterations)...")
    browser.navigate(f"file://{COMPLEX_PAGE}")
    time.sleep(1)
    result = bench("A11y tree (complex page)", lambda: browser.get_accessibility_tree(), 100)
    results.append(result)
    target_met = "✓" if result["median_ms"] < 50 else "✗"
    print(f"  median: {result['median_ms']:.2f}ms (target: <50ms {target_met})")

    # ── Summary table ────────────────────────────────────────────────
    print("\n" + "=" * 90)
    print(f"{'Benchmark':<30} {'Iters':>6} {'Mean':>8} {'Median':>8} {'P95':>8} {'Min':>8} {'Max':>8}")
    print("-" * 90)
    for r in results:
        print(
            f"{r['name']:<30} {r['iterations']:>6} "
            f"{r['mean_ms']:>7.2f}ms {r['median_ms']:>7.2f}ms "
            f"{r['p95_ms']:>7.2f}ms {r['min_ms']:>7.2f}ms {r['max_ms']:>7.2f}ms"
        )
    print("=" * 90)

    # ── Targets ──────────────────────────────────────────────────────
    print("\nTargets (from PRD):")
    js_ok = results[0]["median_ms"] < 2
    ss_ok = results[1]["median_ms"] < 30
    a11y_ok = results[3]["median_ms"] < 50
    print(f"  JS eval <2ms:       {'PASS ✓' if js_ok else 'FAIL ✗'} ({results[0]['median_ms']:.2f}ms)")
    print(f"  Screenshot <30ms:   {'PASS ✓' if ss_ok else 'FAIL ✗'} ({results[1]['median_ms']:.2f}ms)")
    print(f"  A11y tree <50ms:    {'PASS ✓' if a11y_ok else 'FAIL ✗'} ({results[3]['median_ms']:.2f}ms)")

    browser.close()
    print("\nDone.")


if __name__ == "__main__":
    main()
