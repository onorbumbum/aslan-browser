"""Integration tests for the aslan CLI. Requires aslan-browser to be running."""

import json
import os
import subprocess

import pytest


def run_aslan(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Run an aslan CLI command and return the result."""
    return subprocess.run(
        ["aslan", *args],
        capture_output=True,
        text=True,
        check=check,
    )


def test_version():
    r = run_aslan("--version")
    assert "aslan" in r.stdout


def test_status():
    r = run_aslan("status")
    assert "Connected" in r.stdout


def test_nav_and_title():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("title")
    assert "Example Domain" in r.stdout


def test_nav_json():
    r = run_aslan("nav", "https://example.com", "--wait", "load", "--json")
    data = json.loads(r.stdout)
    assert "url" in data
    assert "title" in data


def test_tree():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("tree")
    assert "@e" in r.stdout
    assert '"' in r.stdout  # quoted names


def test_tree_json():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("tree", "--json")
    data = json.loads(r.stdout)
    assert isinstance(data, list)
    assert len(data) > 0
    assert "ref" in data[0]


def test_url():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("url")
    assert "example.com" in r.stdout


def test_text():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("text", "--chars", "200")
    assert "Example Domain" in r.stdout


def test_eval():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("eval", "return document.title")
    assert "Example Domain" in r.stdout


def test_screenshot():
    path = "/tmp/aslan-cli-test.jpg"
    if os.path.exists(path):
        os.remove(path)
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("shot", path)
    assert os.path.exists(path)
    assert "bytes" in r.stdout


def test_click():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("click", "@e0", check=False)
    # @e0 might not be clickable, just verify the command runs
    assert r.returncode == 0 or "Error" in r.stderr


def test_tab_lifecycle():
    r = run_aslan("tab:new", "https://example.com")
    tab_id = r.stdout.strip()
    assert tab_id.startswith("tab")

    r = run_aslan("tabs")
    assert tab_id in r.stdout

    run_aslan("tab:close", tab_id)
    r = run_aslan("tabs")
    assert tab_id not in r.stdout


def test_tab_use():
    r = run_aslan("tab:new")
    tab_id = r.stdout.strip()

    r = run_aslan("tab:use", "tab0")
    assert "Switched to tab0" in r.stdout

    # Clean up
    run_aslan("tab:close", tab_id)


def test_tab_wait():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("tab:wait", "h1", "--timeout", "3000")
    assert "found" in r.stdout


def test_key():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("key", "Tab")
    assert r.returncode == 0


def test_scroll():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("scroll", "--down", "200")
    assert r.returncode == 0
    assert "ok" in r.stdout


def test_source():
    r = run_aslan("source")
    assert "aslan_browser" in r.stdout


def test_back_forward():
    run_aslan("nav", "https://example.com", "--wait", "load")
    # back/forward may not have history but should not crash
    r = run_aslan("back", check=False)
    assert r.returncode == 0 or "Error" in r.stderr
    r = run_aslan("forward", check=False)
    assert r.returncode == 0 or "Error" in r.stderr


def test_reload():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("reload")
    assert r.returncode == 0


def test_html():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("html", "--chars", "500")
    assert "<h1>" in r.stdout or "Example Domain" in r.stdout


def test_html_selector():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("html", "--selector", "h1")
    assert "Example Domain" in r.stdout


def test_type():
    # Type into a page with an input — use eval to create one
    run_aslan("nav", "https://example.com", "--wait", "load")
    run_aslan("eval", "var i = document.createElement('input'); i.id='test-input'; document.body.appendChild(i); return 'ok'")
    r = run_aslan("type", "#test-input", "hello world")
    assert "typed" in r.stdout
    # Verify value was set
    r = run_aslan("eval", 'return document.querySelector("#test-input").value')
    assert "hello world" in r.stdout


def test_wait_load():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("wait", "--load", "--timeout", "5000")
    assert "ready" in r.stdout


def test_wait_idle():
    run_aslan("nav", "https://example.com", "--wait", "load")
    r = run_aslan("wait", "--idle", "--timeout", "5000")
    assert "ready" in r.stdout


def _png_size(path: str) -> tuple[int, int]:
    """Width, height from a PNG's IHDR chunk."""
    import struct
    with open(path, "rb") as f:
        head = f.read(24)
    assert head[:8] == b"\x89PNG\r\n\x1a\n"
    return struct.unpack(">II", head[16:24])


def test_shot_url_single_frame_png():
    path = "/tmp/aslan-cli-shot-frame.png"
    if os.path.exists(path):
        os.remove(path)
    run_aslan("shot", "https://example.com", path, "--width", "800", "--height", "600")
    assert _png_size(path) == (800, 600)


def test_shot_url_full_page_is_taller_than_viewport():
    path = "/tmp/aslan-cli-shot-full.png"
    if os.path.exists(path):
        os.remove(path)
    run_aslan("shot", "https://en.wikipedia.org/wiki/Web_browser", path,
              "--width", "1000", "--full-page")
    w, h = _png_size(path)
    assert w == 1000
    assert h > 720


def test_shot_url_leaves_no_tab_behind():
    before = run_aslan("tabs").stdout
    run_aslan("shot", "https://example.com", "/tmp/aslan-cli-shot-clean.png")
    assert run_aslan("tabs").stdout == before


def test_shot_full_page_with_height_is_rejected():
    r = run_aslan("shot", "https://example.com", "x.png", "--full-page", "--height", "500",
                  check=False)
    assert r.returncode != 0
    assert "not allowed" in r.stderr
