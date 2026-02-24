"""aslan-browser Python SDK — control a native macOS browser from Python."""

from aslan_browser.client import AslanBrowser, AslanBrowserError
from aslan_browser.async_client import AsyncAslanBrowser

__all__ = ["AslanBrowser", "AsyncAslanBrowser", "AslanBrowserError"]
__version__ = "0.5.0"
