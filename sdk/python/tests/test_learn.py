"""
Integration tests for learn mode.
Requires the aslan-browser app to be running.

Usage:
    cd sdk/python && python3 -m pytest tests/test_learn.py -v
"""

import json
import os
import time

import pytest

from aslan_browser import AslanBrowser, AslanBrowserError

SOCKET_PATH = "/tmp/aslan-browser.sock"


@pytest.fixture
def browser():
    """Create a connected sync browser client (no auto session)."""
    b = AslanBrowser(SOCKET_PATH, auto_session=False)
    yield b
    # Safety: always stop recording if still active
    try:
        status = b.learn_status()
        if status.get("recording"):
            b.learn_stop()
    except Exception:
        pass
    b.close()


# ── Status ────────────────────────────────────────────────────────────────


def test_learn_status_default(browser):
    """Learn mode is off by default."""
    status = browser.learn_status()
    assert status["recording"] is False
    assert status["actionCount"] == 0


# ── Start / Stop lifecycle ────────────────────────────────────────────────


def test_learn_start_stop(browser):
    """Start and stop recording."""
    result = browser.learn_start("test-session")
    assert result["ok"] is True
    assert result["name"] == "test-session"
    assert "screenshotDir" in result

    status = browser.learn_status()
    assert status["recording"] is True
    assert status["name"] == "test-session"

    log = browser.learn_stop()
    assert log["name"] == "test-session"
    assert "duration" in log
    assert "actions" in log
    assert isinstance(log["actions"], list)


def test_learn_start_creates_directory(browser):
    """learn.start creates the screenshot directory."""
    result = browser.learn_start("dir-test")
    screenshot_dir = result["screenshotDir"]
    assert os.path.isdir(screenshot_dir)
    browser.learn_stop()


def test_learn_start_cleans_old_directory(browser):
    """learn.start deletes old directory if it exists."""
    browser.learn_start("cleanup-test")
    browser.learn_stop()
    # Start again with same name — should work without error
    result = browser.learn_start("cleanup-test")
    assert result["ok"] is True
    browser.learn_stop()


# ── Error cases ───────────────────────────────────────────────────────────


def test_learn_double_start_fails(browser):
    """Cannot start recording while already recording."""
    browser.learn_start("double-test")
    try:
        with pytest.raises(AslanBrowserError):
            browser.learn_start("another-test")
    finally:
        browser.learn_stop()


def test_learn_stop_when_not_recording_fails(browser):
    """Cannot stop when not recording."""
    with pytest.raises(AslanBrowserError):
        browser.learn_stop()


# ── Navigation capture ────────────────────────────────────────────────────


def test_learn_captures_navigation(browser):
    """Navigation during recording creates action entries."""
    browser.learn_start("nav-test")
    try:
        browser.navigate("https://example.com", wait_until="idle")
        # Give time for screenshot capture (500ms delay + write)
        time.sleep(1.5)
        log = browser.learn_stop()
    except Exception:
        browser.learn_stop()
        raise
    # Should have at least one navigation action
    nav_actions = [a for a in log["actions"] if a.get("type") == "navigation"]
    assert len(nav_actions) >= 1
    assert "example.com" in nav_actions[0].get("url", "")


# ── Screenshots ───────────────────────────────────────────────────────────


def test_learn_screenshot_files_exist(browser):
    """Screenshots are saved to disk during recording."""
    browser.learn_start("screenshot-test")
    try:
        browser.navigate("https://example.com", wait_until="idle")
        time.sleep(2)  # Wait for screenshot capture (500ms delay + file write)
        log = browser.learn_stop()
    except Exception:
        browser.learn_stop()
        raise
    screenshots = [a["screenshot"] for a in log["actions"] if "screenshot" in a]
    assert len(screenshots) >= 1
    for path in screenshots:
        assert os.path.exists(path), f"Missing screenshot: {path}"
