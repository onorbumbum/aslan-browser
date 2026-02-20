"""Synchronous Python client for aslan-browser."""

from __future__ import annotations

import base64
import json
import os
import socket
import time
from typing import Any, Optional


class AslanBrowserError(Exception):
    """Error returned by aslan-browser JSON-RPC server."""

    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message
        super().__init__(f"AslanBrowserError({code}): {message}")


_DEFAULT_SOCKET = "/tmp/aslan-browser.sock"
_RETRY_DELAYS = [0.1, 0.5, 1.0]


class AslanBrowser:
    """Synchronous client for aslan-browser.

    Automatically creates a session on connect and destroys it (closing all
    tabs created by this client) on close.  Pass ``auto_session=False`` to
    opt out and manage sessions manually.

    Usage::

        from aslan_browser import AslanBrowser

        with AslanBrowser() as browser:
            tab = browser.tab_create()
            browser.navigate("https://example.com", tab_id=tab)
            tree = browser.get_accessibility_tree(tab_id=tab)
        # all tabs created by this client are auto-closed here
    """

    def __init__(
        self,
        socket_path: str = _DEFAULT_SOCKET,
        *,
        auto_connect: bool = True,
        auto_session: bool = True,
    ):
        self._socket_path = socket_path
        self._sock: Optional[socket.socket] = None
        self._file = None
        self._next_id = 0
        self._auto_session = auto_session
        self._session_id: Optional[str] = None
        self._owned_tabs: list[str] = []
        if auto_connect:
            self.connect()

    # ── connection management ────────────────────────────────────────

    @property
    def session_id(self) -> Optional[str]:
        """The auto-created session ID, or None if auto_session=False."""
        return self._session_id

    @property
    def owned_tabs(self) -> list[str]:
        """List of tab IDs created by this client (via tab_create)."""
        return list(self._owned_tabs)

    def connect(self) -> None:
        """Connect to the aslan-browser Unix socket with retry."""
        if self._sock is not None:
            return

        last_err: Optional[Exception] = None
        for delay in _RETRY_DELAYS:
            try:
                if not os.path.exists(self._socket_path):
                    raise ConnectionError(
                        f"aslan-browser is not running. Socket not found at {self._socket_path}"
                    )
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.connect(self._socket_path)
                self._sock = sock
                self._file = sock.makefile("rw", encoding="utf-8")

                # Auto-create a session so all tabs are tracked and cleaned up
                if self._auto_session and self._session_id is None:
                    try:
                        result = self._call("session.create", {"name": "sdk-auto"})
                        self._session_id = result.get("sessionId")
                    except Exception:
                        # Server may not support sessions (old binary) — degrade gracefully
                        self._auto_session = False

                return
            except (ConnectionError, OSError) as exc:
                last_err = exc
                time.sleep(delay)

        raise ConnectionError(
            f"Failed to connect to aslan-browser after {len(_RETRY_DELAYS)} attempts: {last_err}"
        )

    def close(self) -> None:
        """Destroy the auto-session (closing all owned tabs) and disconnect."""
        # Clean up session before closing socket
        if self._session_id and self._auto_session:
            try:
                self._call("session.destroy", {"sessionId": self._session_id})
            except Exception:
                pass  # Best-effort; server also cleans up on disconnect
            self._session_id = None
        self._owned_tabs.clear()

        if self._file:
            try:
                self._file.close()
            except OSError:
                pass
            self._file = None
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None

    def __enter__(self) -> "AslanBrowser":
        return self

    def __exit__(self, *_: Any) -> None:
        self.close()

    # ── low-level RPC ────────────────────────────────────────────────

    def _call(self, method: str, params: Optional[dict] = None) -> Any:
        """Send a JSON-RPC request and return the result."""
        if self._sock is None or self._file is None:
            raise ConnectionError("Not connected. Call connect() first.")

        self._next_id += 1
        req_id = self._next_id
        request = {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": method,
            "params": params or {},
        }
        self._file.write(json.dumps(request) + "\n")
        self._file.flush()

        # Read lines, skipping event notifications (no id), until we get our response
        while True:
            line = self._file.readline()
            if not line:
                raise ConnectionError("Connection closed by aslan-browser.")
            response = json.loads(line)
            # Skip notifications (no id field)
            if "id" not in response:
                continue
            if response["id"] == req_id:
                if "error" in response:
                    err = response["error"]
                    raise AslanBrowserError(err["code"], err["message"])
                return response.get("result")

    # ── navigation ───────────────────────────────────────────────────

    def navigate(
        self,
        url: str,
        tab_id: str = "tab0",
        wait_until: str = "load",
        timeout: int = 30000,
    ) -> dict:
        """Navigate to a URL. Returns {"url": ..., "title": ...}."""
        return self._call(
            "navigate",
            {"tabId": tab_id, "url": url, "waitUntil": wait_until, "timeout": timeout},
        )

    def go_back(self, tab_id: str = "tab0") -> dict:
        """Navigate back. Returns {"url": ..., "title": ...}."""
        return self._call("goBack", {"tabId": tab_id})

    def go_forward(self, tab_id: str = "tab0") -> dict:
        """Navigate forward. Returns {"url": ..., "title": ...}."""
        return self._call("goForward", {"tabId": tab_id})

    def reload(self, tab_id: str = "tab0") -> dict:
        """Reload the page. Returns {"url": ..., "title": ...}."""
        return self._call("reload", {"tabId": tab_id})

    def wait_for_selector(
        self, selector: str, tab_id: str = "tab0", timeout: int = 5000
    ) -> dict:
        """Wait for a CSS selector to appear in the DOM."""
        return self._call(
            "waitForSelector",
            {"tabId": tab_id, "selector": selector, "timeout": timeout},
        )

    # ── evaluation ───────────────────────────────────────────────────

    def evaluate(
        self, script: str, tab_id: str = "tab0", args: Optional[dict] = None
    ) -> Any:
        """Evaluate JavaScript and return the result value."""
        params: dict[str, Any] = {"tabId": tab_id, "script": script}
        if args:
            params["args"] = args
        result = self._call("evaluate", params)
        return result.get("value") if result else None

    # ── page info ────────────────────────────────────────────────────

    def get_title(self, tab_id: str = "tab0") -> str:
        """Get the page title."""
        result = self._call("getTitle", {"tabId": tab_id})
        return result.get("title", "")

    def get_url(self, tab_id: str = "tab0") -> str:
        """Get the current URL."""
        result = self._call("getURL", {"tabId": tab_id})
        return result.get("url", "")

    # ── accessibility tree ───────────────────────────────────────────

    def get_accessibility_tree(self, tab_id: str = "tab0") -> list[dict]:
        """Extract the accessibility tree. Returns a list of A11yNode dicts."""
        result = self._call("getAccessibilityTree", {"tabId": tab_id})
        return result.get("tree", [])

    # ── interaction ──────────────────────────────────────────────────

    def click(self, target: str, tab_id: str = "tab0") -> None:
        """Click an element by @eN ref or CSS selector."""
        self._call("click", {"tabId": tab_id, "selector": target})

    def fill(self, target: str, value: str, tab_id: str = "tab0") -> None:
        """Fill an input element with a value."""
        self._call("fill", {"tabId": tab_id, "selector": target, "value": value})

    def select(self, target: str, value: str, tab_id: str = "tab0") -> None:
        """Select an option in a <select> element."""
        self._call("select", {"tabId": tab_id, "selector": target, "value": value})

    def keypress(
        self,
        key: str,
        tab_id: str = "tab0",
        modifiers: Optional[dict[str, bool]] = None,
    ) -> None:
        """Send a keypress event."""
        params: dict[str, Any] = {"tabId": tab_id, "key": key}
        if modifiers:
            params["modifiers"] = modifiers
        self._call("keypress", params)

    def scroll(
        self,
        x: float = 0,
        y: float = 0,
        target: Optional[str] = None,
        tab_id: str = "tab0",
    ) -> None:
        """Scroll the page or a specific element."""
        params: dict[str, Any] = {"tabId": tab_id, "x": x, "y": y}
        if target:
            params["selector"] = target
        self._call("scroll", params)

    # ── screenshots ──────────────────────────────────────────────────

    def screenshot(
        self, tab_id: str = "tab0", quality: int = 70, width: int = 1440
    ) -> bytes:
        """Take a screenshot. Returns JPEG bytes."""
        result = self._call(
            "screenshot", {"tabId": tab_id, "quality": quality, "width": width}
        )
        return base64.b64decode(result["data"])

    def save_screenshot(
        self,
        path: str,
        tab_id: str = "tab0",
        quality: int = 70,
        width: int = 1440,
    ) -> int:
        """Take a screenshot and save it to a file. Returns the file size in bytes."""
        data = self.screenshot(tab_id=tab_id, quality=quality, width=width)
        with open(path, "wb") as f:
            f.write(data)
        return len(data)

    # ── cookies ──────────────────────────────────────────────────────

    def get_cookies(
        self, tab_id: str = "tab0", url: Optional[str] = None
    ) -> list[dict]:
        """Get cookies. Optionally filter by URL."""
        params: dict[str, Any] = {"tabId": tab_id}
        if url:
            params["url"] = url
        result = self._call("getCookies", params)
        return result.get("cookies", [])

    def set_cookie(
        self,
        name: str,
        value: str,
        domain: str,
        path: str = "/",
        expires: Optional[float] = None,
        tab_id: str = "tab0",
    ) -> None:
        """Set a cookie."""
        params: dict[str, Any] = {
            "tabId": tab_id,
            "name": name,
            "value": value,
            "domain": domain,
            "path": path,
        }
        if expires is not None:
            params["expires"] = expires
        self._call("setCookie", params)

    # ── tab management ───────────────────────────────────────────────

    def tab_create(
        self,
        url: Optional[str] = None,
        width: int = 1440,
        height: int = 900,
        hidden: Optional[bool] = None,
        session_id: Optional[str] = None,
    ) -> str:
        """Create a new tab. Returns the tab ID.

        If auto_session is enabled and no explicit session_id is given,
        the tab is automatically tagged to this client's session and will
        be closed when the client disconnects.
        """
        params: dict[str, Any] = {"width": width, "height": height}
        if url:
            params["url"] = url
        if hidden is not None:
            params["hidden"] = hidden
        # Auto-tag with this client's session unless caller specified one
        effective_session = session_id or self._session_id
        if effective_session:
            params["sessionId"] = effective_session
        result = self._call("tab.create", params)
        tab_id = result["tabId"]
        self._owned_tabs.append(tab_id)
        return tab_id

    def tab_close(self, tab_id: str) -> None:
        """Close a tab and remove it from local tracking."""
        self._call("tab.close", {"tabId": tab_id})
        try:
            self._owned_tabs.remove(tab_id)
        except ValueError:
            pass  # Tab wasn't created by this client (e.g. tab0)

    def tab_list(self, session_id: Optional[str] = None) -> list[dict]:
        """List all open tabs. Optionally filter by session."""
        params: dict[str, Any] = {}
        if session_id:
            params["sessionId"] = session_id
        result = self._call("tab.list", params)
        return result.get("tabs", [])

    # ── sessions ─────────────────────────────────────────────────────

    def session_create(self, name: Optional[str] = None) -> str:
        """Create a new session. Returns the session ID."""
        params: dict[str, Any] = {}
        if name:
            params["name"] = name
        result = self._call("session.create", params)
        return result["sessionId"]

    def session_destroy(self, session_id: str) -> list[str]:
        """Destroy a session and close all its tabs. Returns closed tab IDs."""
        result = self._call("session.destroy", {"sessionId": session_id})
        closed = result.get("closedTabs", [])
        # Remove closed tabs from local tracking
        for tab_id in closed:
            try:
                self._owned_tabs.remove(tab_id)
            except ValueError:
                pass
        return closed

    # ── batch operations ─────────────────────────────────────────────

    def batch(self, requests: list[dict]) -> list[dict]:
        """Execute multiple requests in one round-trip.

        Args:
            requests: List of {"method": ..., "params": ...} dicts.

        Returns:
            List of {"result": ...} or {"error": ...} dicts, in same order.
        """
        result = self._call("batch", {"requests": requests})
        return result.get("responses", [])

    def parallel_get_trees(self, tab_ids: list[str]) -> dict[str, list[dict]]:
        """Get accessibility trees from multiple tabs in one call.

        Returns:
            Dict mapping tab_id → tree (list of A11yNode dicts).
            If a tab errored, its value is an empty list.
        """
        requests = [
            {"method": "getAccessibilityTree", "params": {"tabId": tid}}
            for tid in tab_ids
        ]
        responses = self.batch(requests)
        result = {}
        for tid, resp in zip(tab_ids, responses):
            if "result" in resp:
                result[tid] = resp["result"].get("tree", [])
            else:
                result[tid] = []
        return result

    def parallel_navigate(
        self,
        urls: dict[str, str],
        wait_until: str = "load",
    ) -> dict[str, dict]:
        """Navigate multiple tabs to different URLs in one call.

        Args:
            urls: Dict mapping tab_id → URL.
            wait_until: "load", "idle", or "none".

        Returns:
            Dict mapping tab_id → {"url": ..., "title": ...} or {"error": ...}.
        """
        requests = [
            {"method": "navigate", "params": {"tabId": tid, "url": url, "waitUntil": wait_until}}
            for tid, url in urls.items()
        ]
        responses = self.batch(requests)
        result = {}
        for (tid, _), resp in zip(urls.items(), responses):
            if "result" in resp:
                result[tid] = resp["result"]
            else:
                result[tid] = resp.get("error", {"message": "Unknown error"})
        return result

    def parallel_screenshots(
        self, tab_ids: list[str], quality: int = 70, width: int = 1440
    ) -> dict[str, bytes]:
        """Take screenshots of multiple tabs in one call.

        Returns:
            Dict mapping tab_id → JPEG bytes. Errored tabs omitted.
        """
        requests = [
            {"method": "screenshot", "params": {"tabId": tid, "quality": quality, "width": width}}
            for tid in tab_ids
        ]
        responses = self.batch(requests)
        result = {}
        for tid, resp in zip(tab_ids, responses):
            if "result" in resp and "data" in resp["result"]:
                result[tid] = base64.b64decode(resp["result"]["data"])
        return result
