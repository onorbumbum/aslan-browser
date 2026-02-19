"""Phase 7 integration tests — sessions, batch operations, window controls.

Requirements:
    - aslan-browser must be running before executing these tests.
    - Python SDK must be installed: pip install -e sdk/python/

Manual tests (cannot be automated via JSON-RPC):
    - Cmd+V paste: Launch app, navigate to a login page, click password field,
      press Cmd+V. Should paste clipboard content.
    - Close button: Click the red close button on a tab window. The tab should
      be removed from tab.list.
    - Address bar: Type a URL in the address bar and press Enter. The page
      should navigate and the URL bar should update.

Run:
    python3 -m pytest tests/test_phase7.py -v
"""

import time

import pytest

from aslan_browser import AslanBrowser


@pytest.fixture
def browser():
    """Create a fresh AslanBrowser connection for each test."""
    b = AslanBrowser()
    yield b
    b.close()


# ── Session Tests ────────────────────────────────────────────────────


def test_session_create(browser: AslanBrowser):
    """session.create returns a session ID."""
    sid = browser.session_create(name="test-agent")
    assert sid.startswith("s")


def test_session_lifecycle(browser: AslanBrowser):
    """Create session, add tabs, filter by session, destroy session."""
    sid = browser.session_create(name="test-agent")

    t1 = browser.tab_create(url="https://example.com", session_id=sid)
    t2 = browser.tab_create(url="https://example.org", session_id=sid)

    # Wait for navigation
    time.sleep(2)

    # List with session filter
    session_tabs = browser.tab_list(session_id=sid)
    session_tab_ids = [t["tabId"] for t in session_tabs]
    assert t1 in session_tab_ids
    assert t2 in session_tab_ids
    assert len(session_tabs) == 2

    # List without filter should include all tabs (tab0 + t1 + t2)
    all_tabs = browser.tab_list()
    assert len(all_tabs) >= 3

    # Destroy session
    closed = browser.session_destroy(sid)
    assert set(closed) == {t1, t2}

    # Tabs are gone
    remaining = browser.tab_list()
    remaining_ids = [t["tabId"] for t in remaining]
    assert t1 not in remaining_ids
    assert t2 not in remaining_ids


def test_session_destroy_nonexistent(browser: AslanBrowser):
    """Destroying a non-existent session raises an error."""
    from aslan_browser import AslanBrowserError

    with pytest.raises(AslanBrowserError) as exc_info:
        browser.session_destroy("s9999")
    assert exc_info.value.code == -32004


# ── Batch Tests ──────────────────────────────────────────────────────


def test_batch_basic(browser: AslanBrowser):
    """Batch request with multiple getTitle/getURL calls."""
    responses = browser.batch([
        {"method": "getTitle", "params": {"tabId": "tab0"}},
        {"method": "getURL", "params": {"tabId": "tab0"}},
    ])
    assert len(responses) == 2
    assert "result" in responses[0]
    assert "result" in responses[1]
    assert "title" in responses[0]["result"]
    assert "url" in responses[1]["result"]


def test_batch_partial_error(browser: AslanBrowser):
    """Batch request with one valid and one invalid tab."""
    responses = browser.batch([
        {"method": "getTitle", "params": {"tabId": "tab0"}},
        {"method": "getTitle", "params": {"tabId": "nonexistent"}},
    ])
    assert len(responses) == 2
    assert "result" in responses[0]
    assert "error" in responses[1]


def test_batch_nested_rejected(browser: AslanBrowser):
    """Nested batch calls are rejected."""
    responses = browser.batch([
        {"method": "batch", "params": {"requests": []}},
    ])
    assert len(responses) == 1
    assert "error" in responses[0]
    assert "Nested batch" in responses[0]["error"]["message"]


def test_batch_missing_method(browser: AslanBrowser):
    """Batch sub-request without method returns error."""
    responses = browser.batch([
        {"params": {"tabId": "tab0"}},
    ])
    assert len(responses) == 1
    assert "error" in responses[0]


def test_parallel_get_trees(browser: AslanBrowser):
    """parallel_get_trees fetches trees from multiple tabs."""
    t1 = browser.tab_create(url="https://example.com")
    t2 = browser.tab_create(url="https://example.org")
    time.sleep(2)  # Wait for pages to load

    trees = browser.parallel_get_trees([t1, t2])
    assert t1 in trees
    assert t2 in trees
    assert len(trees[t1]) > 0
    assert len(trees[t2]) > 0

    # Cleanup
    browser.tab_close(t1)
    browser.tab_close(t2)


def test_parallel_navigate(browser: AslanBrowser):
    """parallel_navigate navigates multiple tabs at once."""
    t1 = browser.tab_create()
    t2 = browser.tab_create()

    results = browser.parallel_navigate({
        t1: "https://example.com",
        t2: "https://example.org",
    })
    assert t1 in results
    assert t2 in results
    assert "url" in results[t1]
    assert "url" in results[t2]

    # Cleanup
    browser.tab_close(t1)
    browser.tab_close(t2)


# ── Window Title Test ────────────────────────────────────────────────


def test_window_title_updates(browser: AslanBrowser):
    """After navigation, getTitle returns the page title."""
    browser.navigate("https://example.com")
    time.sleep(1)
    title = browser.get_title()
    assert "Example" in title


# ── Tab Create with Session ──────────────────────────────────────────


def test_tab_create_with_session(browser: AslanBrowser):
    """Tabs created with session_id are filtered correctly."""
    sid = browser.session_create()
    t1 = browser.tab_create(session_id=sid)

    session_tabs = browser.tab_list(session_id=sid)
    assert len(session_tabs) == 1
    assert session_tabs[0]["tabId"] == t1

    # tab0 should NOT be in this session
    tab0_found = any(t["tabId"] == "tab0" for t in session_tabs)
    assert not tab0_found

    # Cleanup
    browser.session_destroy(sid)
