"""Asynchronous Python client for aslan-browser."""

from __future__ import annotations

import asyncio
import base64
import json
import os
from typing import Any, Callable, Optional

from aslan_browser.client import AslanBrowserError


_DEFAULT_SOCKET = "/tmp/aslan-browser.sock"
_RETRY_DELAYS = [0.1, 0.5, 1.0]


class AsyncAslanBrowser:
    """Async client for aslan-browser.

    Automatically creates a session on connect and destroys it (closing all
    tabs created by this client) on close.  Pass ``auto_session=False`` to
    opt out and manage sessions manually.

    Usage::

        from aslan_browser import AsyncAslanBrowser

        async with AsyncAslanBrowser() as browser:
            tab = await browser.tab_create()
            await browser.navigate("https://example.com", tab_id=tab)
            tree = await browser.get_accessibility_tree(tab_id=tab)
        # all tabs created by this client are auto-closed here
    """

    def __init__(self, socket_path: str = _DEFAULT_SOCKET, *, auto_session: bool = True):
        self._socket_path = socket_path
        self._reader: Optional[asyncio.StreamReader] = None
        self._writer: Optional[asyncio.StreamWriter] = None
        self._next_id = 0
        self._pending: dict[int, asyncio.Future] = {}
        self._read_task: Optional[asyncio.Task] = None
        self._on_event: Optional[Callable[[dict], Any]] = None
        self._auto_session = auto_session
        self._session_id: Optional[str] = None
        self._owned_tabs: list[str] = []

    # ── connection management ────────────────────────────────────────

    @property
    def session_id(self) -> Optional[str]:
        """The auto-created session ID, or None if auto_session=False."""
        return self._session_id

    @property
    def owned_tabs(self) -> list[str]:
        """List of tab IDs created by this client (via tab_create)."""
        return list(self._owned_tabs)

    async def connect(self) -> None:
        """Connect to the aslan-browser Unix socket with retry."""
        if self._reader is not None:
            return

        last_err: Optional[Exception] = None
        for delay in _RETRY_DELAYS:
            try:
                if not os.path.exists(self._socket_path):
                    raise ConnectionError(
                        f"aslan-browser is not running. Socket not found at {self._socket_path}"
                    )
                self._reader, self._writer = await asyncio.open_unix_connection(
                    self._socket_path
                )
                self._read_task = asyncio.create_task(self._read_loop())

                # Auto-create a session so all tabs are tracked and cleaned up
                if self._auto_session and self._session_id is None:
                    try:
                        result = await self._call("session.create", {"name": "sdk-auto"})
                        self._session_id = result.get("sessionId")
                    except Exception:
                        self._auto_session = False

                return
            except (ConnectionError, OSError) as exc:
                last_err = exc
                await asyncio.sleep(delay)

        raise ConnectionError(
            f"Failed to connect to aslan-browser after {len(_RETRY_DELAYS)} attempts: {last_err}"
        )

    async def close(self) -> None:
        """Destroy the auto-session (closing all owned tabs) and disconnect."""
        # Clean up session before closing socket
        if self._session_id and self._auto_session:
            try:
                await self._call("session.destroy", {"sessionId": self._session_id})
            except Exception:
                pass  # Best-effort; server also cleans up on disconnect
            self._session_id = None
        self._owned_tabs.clear()

        if self._read_task:
            self._read_task.cancel()
            try:
                await self._read_task
            except asyncio.CancelledError:
                pass
            self._read_task = None

        if self._writer:
            try:
                self._writer.close()
                await self._writer.wait_closed()
            except OSError:
                pass
            self._writer = None
        self._reader = None

        # Fail any pending requests
        for fut in self._pending.values():
            if not fut.done():
                fut.set_exception(ConnectionError("Connection closed."))
        self._pending.clear()

    async def __aenter__(self) -> "AsyncAslanBrowser":
        await self.connect()
        return self

    async def __aexit__(self, *_: Any) -> None:
        await self.close()

    def on_event(self, callback: Callable[[dict], Any]) -> None:
        """Register a callback for JSON-RPC notifications (events)."""
        self._on_event = callback

    # ── read loop ────────────────────────────────────────────────────

    async def _read_loop(self) -> None:
        """Background task that reads responses and routes them."""
        assert self._reader is not None
        try:
            while True:
                line = await self._reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if "id" in msg and msg["id"] in self._pending:
                    self._pending[msg["id"]].set_result(msg)
                elif "method" in msg:
                    # Notification / event
                    if self._on_event:
                        try:
                            result = self._on_event(msg)
                            if asyncio.iscoroutine(result):
                                await result
                        except Exception:
                            pass
        except asyncio.CancelledError:
            raise
        except Exception:
            pass
        finally:
            # Connection lost — fail pending
            for fut in self._pending.values():
                if not fut.done():
                    fut.set_exception(ConnectionError("Connection lost."))
            self._pending.clear()

    # ── low-level RPC ────────────────────────────────────────────────

    async def _call(self, method: str, params: Optional[dict] = None) -> Any:
        """Send a JSON-RPC request and return the result."""
        if self._writer is None:
            raise ConnectionError("Not connected. Call connect() first.")

        self._next_id += 1
        req_id = self._next_id
        request = {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": method,
            "params": params or {},
        }

        future: asyncio.Future = asyncio.get_event_loop().create_future()
        self._pending[req_id] = future

        self._writer.write((json.dumps(request) + "\n").encode("utf-8"))
        await self._writer.drain()

        try:
            response = await future
        finally:
            self._pending.pop(req_id, None)

        if "error" in response:
            err = response["error"]
            raise AslanBrowserError(err["code"], err["message"])
        return response.get("result")

    # ── navigation ───────────────────────────────────────────────────

    async def navigate(
        self,
        url: str,
        tab_id: str = "tab0",
        wait_until: str = "load",
        timeout: int = 30000,
    ) -> dict:
        """Navigate to a URL. Returns {"url": ..., "title": ...}."""
        return await self._call(
            "navigate",
            {"tabId": tab_id, "url": url, "waitUntil": wait_until, "timeout": timeout},
        )

    async def go_back(self, tab_id: str = "tab0") -> dict:
        """Navigate back."""
        return await self._call("goBack", {"tabId": tab_id})

    async def go_forward(self, tab_id: str = "tab0") -> dict:
        """Navigate forward."""
        return await self._call("goForward", {"tabId": tab_id})

    async def reload(self, tab_id: str = "tab0") -> dict:
        """Reload the page."""
        return await self._call("reload", {"tabId": tab_id})

    async def wait_for_selector(
        self, selector: str, tab_id: str = "tab0", timeout: int = 5000
    ) -> dict:
        """Wait for a CSS selector to appear in the DOM."""
        return await self._call(
            "waitForSelector",
            {"tabId": tab_id, "selector": selector, "timeout": timeout},
        )

    # ── evaluation ───────────────────────────────────────────────────

    async def evaluate(
        self, script: str, tab_id: str = "tab0", args: Optional[dict] = None
    ) -> Any:
        """Evaluate JavaScript and return the result value."""
        params: dict[str, Any] = {"tabId": tab_id, "script": script}
        if args:
            params["args"] = args
        result = await self._call("evaluate", params)
        return result.get("value") if result else None

    # ── page info ────────────────────────────────────────────────────

    async def get_title(self, tab_id: str = "tab0") -> str:
        """Get the page title."""
        result = await self._call("getTitle", {"tabId": tab_id})
        return result.get("title", "")

    async def get_url(self, tab_id: str = "tab0") -> str:
        """Get the current URL."""
        result = await self._call("getURL", {"tabId": tab_id})
        return result.get("url", "")

    # ── accessibility tree ───────────────────────────────────────────

    async def get_accessibility_tree(self, tab_id: str = "tab0") -> list[dict]:
        """Extract the accessibility tree."""
        result = await self._call("getAccessibilityTree", {"tabId": tab_id})
        return result.get("tree", [])

    # ── interaction ──────────────────────────────────────────────────

    async def click(self, target: str, tab_id: str = "tab0") -> None:
        """Click an element by @eN ref or CSS selector."""
        await self._call("click", {"tabId": tab_id, "selector": target})

    async def fill(self, target: str, value: str, tab_id: str = "tab0") -> None:
        """Fill an input element."""
        await self._call("fill", {"tabId": tab_id, "selector": target, "value": value})

    async def select(self, target: str, value: str, tab_id: str = "tab0") -> None:
        """Select an option in a <select> element."""
        await self._call(
            "select", {"tabId": tab_id, "selector": target, "value": value}
        )

    async def keypress(
        self,
        key: str,
        tab_id: str = "tab0",
        modifiers: Optional[dict[str, bool]] = None,
    ) -> None:
        """Send a keypress event."""
        params: dict[str, Any] = {"tabId": tab_id, "key": key}
        if modifiers:
            params["modifiers"] = modifiers
        await self._call("keypress", params)

    async def scroll(
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
        await self._call("scroll", params)

    # ── screenshots ──────────────────────────────────────────────────

    async def screenshot(
        self, tab_id: str = "tab0", quality: int = 70, width: int = 1440
    ) -> bytes:
        """Take a screenshot. Returns JPEG bytes."""
        result = await self._call(
            "screenshot", {"tabId": tab_id, "quality": quality, "width": width}
        )
        return base64.b64decode(result["data"])

    async def save_screenshot(
        self,
        path: str,
        tab_id: str = "tab0",
        quality: int = 70,
        width: int = 1440,
    ) -> int:
        """Take a screenshot and save to a file. Returns file size in bytes."""
        data = await self.screenshot(tab_id=tab_id, quality=quality, width=width)
        with open(path, "wb") as f:
            f.write(data)
        return len(data)

    # ── cookies ──────────────────────────────────────────────────────

    async def get_cookies(
        self, tab_id: str = "tab0", url: Optional[str] = None
    ) -> list[dict]:
        """Get cookies."""
        params: dict[str, Any] = {"tabId": tab_id}
        if url:
            params["url"] = url
        result = await self._call("getCookies", params)
        return result.get("cookies", [])

    async def set_cookie(
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
        await self._call("setCookie", params)

    # ── tab management ───────────────────────────────────────────────

    async def tab_create(
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
        result = await self._call("tab.create", params)
        tab_id = result["tabId"]
        self._owned_tabs.append(tab_id)
        return tab_id

    async def tab_close(self, tab_id: str) -> None:
        """Close a tab and remove it from local tracking."""
        await self._call("tab.close", {"tabId": tab_id})
        try:
            self._owned_tabs.remove(tab_id)
        except ValueError:
            pass  # Tab wasn't created by this client (e.g. tab0)

    async def tab_list(self, session_id: Optional[str] = None) -> list[dict]:
        """List all open tabs. Optionally filter by session."""
        params: dict[str, Any] = {}
        if session_id:
            params["sessionId"] = session_id
        result = await self._call("tab.list", params)
        return result.get("tabs", [])

    # ── sessions ─────────────────────────────────────────────────────

    async def session_create(self, name: Optional[str] = None) -> str:
        """Create a new session. Returns the session ID."""
        params: dict[str, Any] = {}
        if name:
            params["name"] = name
        result = await self._call("session.create", params)
        return result["sessionId"]

    async def session_destroy(self, session_id: str) -> list[str]:
        """Destroy a session and close all its tabs. Returns closed tab IDs."""
        result = await self._call("session.destroy", {"sessionId": session_id})
        closed = result.get("closedTabs", [])
        # Remove closed tabs from local tracking
        for tab_id in closed:
            try:
                self._owned_tabs.remove(tab_id)
            except ValueError:
                pass
        return closed

    # ── batch operations ─────────────────────────────────────────────

    async def batch(self, requests: list[dict]) -> list[dict]:
        """Execute multiple requests in one round-trip.

        Args:
            requests: List of {"method": ..., "params": ...} dicts.

        Returns:
            List of {"result": ...} or {"error": ...} dicts, in same order.
        """
        result = await self._call("batch", {"requests": requests})
        return result.get("responses", [])

    async def parallel_get_trees(self, tab_ids: list[str]) -> dict[str, list[dict]]:
        """Get accessibility trees from multiple tabs in one call.

        Returns:
            Dict mapping tab_id → tree (list of A11yNode dicts).
            If a tab errored, its value is an empty list.
        """
        requests = [
            {"method": "getAccessibilityTree", "params": {"tabId": tid}}
            for tid in tab_ids
        ]
        responses = await self.batch(requests)
        result = {}
        for tid, resp in zip(tab_ids, responses):
            if "result" in resp:
                result[tid] = resp["result"].get("tree", [])
            else:
                result[tid] = []
        return result

    async def parallel_navigate(
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
        responses = await self.batch(requests)
        result = {}
        for (tid, _), resp in zip(urls.items(), responses):
            if "result" in resp:
                result[tid] = resp["result"]
            else:
                result[tid] = resp.get("error", {"message": "Unknown error"})
        return result

    async def parallel_screenshots(
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
        responses = await self.batch(requests)
        result = {}
        for tid, resp in zip(tab_ids, responses):
            if "result" in resp and "data" in resp["result"]:
                result[tid] = base64.b64decode(resp["result"]["data"])
        return result
