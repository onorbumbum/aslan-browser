"""
Integration tests for aslan-browser Python SDK.
Requires the aslan-browser app to be running.

Usage:
    cd sdk/python && python3 -m pytest tests/ -v
"""

import asyncio
import os
import tempfile
import time

import pytest
import pytest_asyncio

from aslan_browser import AslanBrowser, AsyncAslanBrowser, AslanBrowserError

SOCKET_PATH = "/tmp/aslan-browser.sock"


@pytest.fixture
def browser():
    """Create a connected sync browser client."""
    b = AslanBrowser(SOCKET_PATH)
    yield b
    b.close()


@pytest_asyncio.fixture
async def async_browser():
    """Create a connected async browser client."""
    b = AsyncAslanBrowser(SOCKET_PATH)
    await b.connect()
    yield b
    await b.close()


# ── Sync client tests ────────────────────────────────────────────────────


class TestSyncNavigation:
    def test_navigate(self, browser):
        result = browser.navigate("https://example.com")
        assert "example.com" in result["url"]

    def test_get_title(self, browser):
        browser.navigate("https://example.com")
        title = browser.get_title()
        assert isinstance(title, str)
        assert len(title) > 0

    def test_get_url(self, browser):
        browser.navigate("https://example.com")
        url = browser.get_url()
        assert "example.com" in url

    def test_go_back_forward(self, browser):
        browser.navigate("https://example.com")
        browser.navigate("https://www.iana.org/domains/reserved")
        result = browser.go_back()
        assert "example.com" in result["url"]
        result = browser.go_forward()
        assert "iana.org" in result["url"]

    def test_reload(self, browser):
        browser.navigate("https://example.com")
        result = browser.reload()
        assert "example.com" in result["url"]


class TestSyncEvaluation:
    def test_evaluate(self, browser):
        browser.navigate("https://example.com")
        result = browser.evaluate("return 1 + 1")
        assert result == 2

    def test_evaluate_string(self, browser):
        browser.navigate("https://example.com")
        result = browser.evaluate("return document.title")
        assert isinstance(result, str)


class TestSyncAccessibilityTree:
    def test_get_tree(self, browser):
        browser.navigate("https://example.com")
        time.sleep(0.5)
        tree = browser.get_accessibility_tree()
        assert isinstance(tree, list)
        assert len(tree) > 0

    def test_tree_node_structure(self, browser):
        browser.navigate("https://example.com")
        time.sleep(0.5)
        tree = browser.get_accessibility_tree()
        node = tree[0]
        assert "ref" in node
        assert "role" in node
        assert "name" in node


class TestSyncInteraction:
    def test_click_by_ref(self, browser):
        browser.navigate("https://example.com")
        time.sleep(0.5)
        tree = browser.get_accessibility_tree()
        links = [n for n in tree if n["role"] == "link"]
        assert len(links) > 0
        browser.click(links[0]["ref"])  # Should not raise

    def test_fill(self, browser):
        browser.navigate("https://example.com")
        time.sleep(0.5)
        browser.evaluate(
            "var i = document.createElement('input'); i.id='sdk-test'; document.body.appendChild(i); return true;"
        )
        browser.fill("#sdk-test", "hello from SDK")
        result = browser.evaluate("return document.getElementById('sdk-test').value")
        assert result == "hello from SDK"


class TestSyncScreenshot:
    def test_screenshot_bytes(self, browser):
        browser.navigate("https://example.com")
        time.sleep(1)
        data = browser.screenshot(quality=50, width=800)
        assert isinstance(data, bytes)
        assert len(data) > 100
        assert data[:2] == b"\xff\xd8"  # JPEG magic bytes

    def test_save_screenshot(self, browser):
        browser.navigate("https://example.com")
        time.sleep(1)
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            path = f.name
        try:
            size = browser.save_screenshot(path, quality=50, width=800)
            assert size > 100
            assert os.path.exists(path)
            with open(path, "rb") as f:
                assert f.read(2) == b"\xff\xd8"
        finally:
            os.unlink(path)


class TestSyncCookies:
    def test_set_and_get_cookie(self, browser):
        browser.navigate("https://example.com")
        time.sleep(0.5)
        browser.set_cookie("sdk_test", "sdk_value", ".example.com")
        cookies = browser.get_cookies(url="https://example.com")
        found = [c for c in cookies if c["name"] == "sdk_test"]
        assert len(found) > 0
        assert found[0]["value"] == "sdk_value"


class TestSyncTabs:
    def test_tab_list(self, browser):
        tabs = browser.tab_list()
        assert isinstance(tabs, list)
        assert len(tabs) >= 1
        tab_ids = [t["tabId"] for t in tabs]
        assert "tab0" in tab_ids

    def test_tab_create_and_close(self, browser):
        tab_id = browser.tab_create(url="https://example.com")
        assert tab_id.startswith("tab")

        tabs = browser.tab_list()
        tab_ids = [t["tabId"] for t in tabs]
        assert tab_id in tab_ids

        browser.tab_close(tab_id)
        tabs = browser.tab_list()
        tab_ids = [t["tabId"] for t in tabs]
        assert tab_id not in tab_ids


class TestSyncErrors:
    def test_invalid_method(self, browser):
        with pytest.raises(AslanBrowserError) as exc_info:
            browser._call("nonexistent_method")
        assert exc_info.value.code == -32601

    def test_missing_params(self, browser):
        with pytest.raises(AslanBrowserError) as exc_info:
            browser._call("navigate", {})
        assert exc_info.value.code == -32602

    def test_tab_not_found(self, browser):
        with pytest.raises(AslanBrowserError) as exc_info:
            browser.navigate("https://example.com", tab_id="nonexistent")
        assert exc_info.value.code == -32000


class TestSyncContextManager:
    def test_with_statement(self):
        with AslanBrowser(SOCKET_PATH) as browser:
            result = browser.navigate("https://example.com")
            assert "example.com" in result["url"]


class TestSyncConnectionError:
    def test_bad_socket_path(self):
        with pytest.raises(ConnectionError, match="not running"):
            AslanBrowser("/tmp/nonexistent-aslan.sock")


# ── Async client tests ──────────────────────────────────────────────────


class TestAsyncNavigation:
    async def test_navigate(self, async_browser):
        result = await async_browser.navigate("https://example.com")
        assert "example.com" in result["url"]

    async def test_get_title(self, async_browser):
        await async_browser.navigate("https://example.com")
        title = await async_browser.get_title()
        assert isinstance(title, str)
        assert len(title) > 0


class TestAsyncAccessibilityTree:
    async def test_get_tree(self, async_browser):
        await async_browser.navigate("https://example.com")
        await asyncio.sleep(0.5)
        tree = await async_browser.get_accessibility_tree()
        assert isinstance(tree, list)
        assert len(tree) > 0


class TestAsyncScreenshot:
    async def test_screenshot_bytes(self, async_browser):
        await async_browser.navigate("https://example.com")
        await asyncio.sleep(1)
        data = await async_browser.screenshot(quality=50, width=800)
        assert isinstance(data, bytes)
        assert len(data) > 100
        assert data[:2] == b"\xff\xd8"


class TestAsyncTabs:
    async def test_tab_create_and_close(self, async_browser):
        tab_id = await async_browser.tab_create(url="https://example.com")
        assert tab_id.startswith("tab")
        await async_browser.tab_close(tab_id)


class TestAsyncContextManager:
    async def test_async_with(self):
        async with AsyncAslanBrowser(SOCKET_PATH) as browser:
            result = await browser.navigate("https://example.com")
            assert "example.com" in result["url"]


class TestAsyncEvents:
    async def test_event_callback(self, async_browser):
        events = []
        async_browser.on_event(lambda e: events.append(e))
        await async_browser.navigate("https://example.com")
        await asyncio.sleep(0.5)
        await async_browser.evaluate("console.log('async event test'); return true;")
        await asyncio.sleep(0.5)
        # Events may or may not arrive depending on timing — just verify no crash
