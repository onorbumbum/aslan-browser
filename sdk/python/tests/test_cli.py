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
