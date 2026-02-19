"""
Manual Test — Phase 7
Search Google for "dentists in Arroyo Grande" and open results in tabs.
"""

import sys
import time
import json

sys.path.insert(0, "/Users/onorbumbum/_PROJECTS/aslan-browser/aslan-browser/sdk/python")
from aslan_browser import AslanBrowser


def flatten_tree(nodes, results=None, depth=0):
    """Recursively flatten accessibility tree into a list."""
    if results is None:
        results = []
    for node in nodes:
        results.append(node)
        if node.get("children"):
            flatten_tree(node["children"], results, depth + 1)
    return results


def find_search_result_links(tree_nodes):
    """Find organic search result links from flattened a11y tree."""
    links = []
    for node in tree_nodes:
        role = node.get("role", "")
        url = node.get("url", "") or node.get("href", "")
        name = node.get("name", "").strip()

        # Look for link nodes that are real organic results
        # Google organic results have URLs starting with http (not google internal)
        if role == "link" and url and name:
            if (url.startswith("http") and
                "google.com" not in url and
                "youtube.com" not in url.lower() or "dentist" in name.lower()):
                # Filter for real external links
                if ("google.com" not in url and
                    url.startswith("http") and
                    len(name) > 10):
                    if url not in [l["url"] for l in links]:
                        links.append({"name": name, "url": url})
    return links


def main():
    print("=" * 60)
    print("🦁 Aslan Browser — Manual Test: Google Search + Open Tabs")
    print("=" * 60)

    with AslanBrowser() as browser:
        # ── Step 1: List current tabs ─────────────────────────────
        tabs = browser.tab_list()
        print(f"\n📋 Current tabs: {[t['tabId'] for t in tabs]}")

        # ── Step 2: Navigate tab0 to Google ───────────────────────
        print("\n🌐 Step 1: Navigating tab0 to Google...")
        nav = browser.navigate("https://www.google.com", tab_id="tab0", wait_until="load")
        print(f"   ✅ Loaded: {nav.get('title', '')} — {nav.get('url', '')}")

        time.sleep(1)

        # ── Step 3: Take a screenshot for reference ────────────────
        print("\n📸 Step 2: Taking screenshot of Google homepage...")
        browser.save_screenshot("/tmp/aslan_test_google_home.jpg", tab_id="tab0")
        print("   ✅ Saved to /tmp/aslan_test_google_home.jpg")

        # ── Step 4: Find search box ref then fill ─────────────────
        search_query = "dentists in Arroyo Grande"
        print(f"\n🔍 Step 3: Searching for '{search_query}'...")

        # Get accessibility tree to find the search box ref
        tree = browser.get_accessibility_tree(tab_id="tab0")

        def find_search_ref(nodes):
            for n in nodes:
                role = n.get("role", "")
                if role in ["textbox", "searchbox", "combobox", "textField", "searchField"]:
                    return n.get("ref")
                ref = find_search_ref(n.get("children", []))
                if ref:
                    return ref
            return None

        search_ref = find_search_ref(tree)
        print(f"   Found search box ref: {search_ref}")

        # Fill via ref (a11y-based, no CSS selector needed)
        browser.fill(search_ref, search_query, tab_id="tab0")
        print(f"   ✅ Filled search box with '{search_query}'")

        # Press Enter to search
        browser.keypress("Return", tab_id="tab0")
        print(f"   ✅ Pressed Enter — waiting for results...")
        time.sleep(3)  # Wait for results to load

        # ── Step 5: Screenshot the results ────────────────────────
        browser.save_screenshot("/tmp/aslan_test_google_results.jpg", tab_id="tab0")
        print("   ✅ Saved results screenshot to /tmp/aslan_test_google_results.jpg")

        current_url = browser.get_url(tab_id="tab0")
        current_title = browser.get_title(tab_id="tab0")
        print(f"   📍 URL: {current_url}")
        print(f"   📄 Title: {current_title}")

        # ── Step 6: Get accessibility tree to find result links ────
        print("\n🌳 Step 4: Reading accessibility tree to find result links...")
        tree = browser.get_accessibility_tree(tab_id="tab0")
        flat = flatten_tree(tree)
        print(f"   Found {len(flat)} nodes in accessibility tree")

        # Find organic result links
        result_links = find_search_result_links(flat)
        print(f"   Found {len(result_links)} candidate result links")

        # Also try a JS approach to get the actual search result URLs
        print("\n🔎 Step 5: Using JS to extract top search result URLs...")
        js_links = browser.evaluate("""
            (function() {
                var results = [];
                // Google result links - look for cite elements near h3
                var anchors = document.querySelectorAll('a[href]');
                for (var i = 0; i < anchors.length; i++) {
                    var a = anchors[i];
                    var href = a.href;
                    var text = a.innerText || a.textContent || '';
                    text = text.trim();
                    // Only external links with meaningful text, not google internal
                    if (href.startsWith('http') &&
                        !href.includes('google.com') &&
                        text.length > 5 &&
                        text.length < 200) {
                        // Check if it looks like a result (has an h3 nearby or is in a result div)
                        var parent = a.closest('[data-ved]') || a.closest('.g');
                        if (parent) {
                            results.push({url: href, text: text.substring(0, 80)});
                        }
                    }
                }
                // Deduplicate by URL
                var seen = {};
                var unique = [];
                for (var j = 0; j < results.length; j++) {
                    if (!seen[results[j].url]) {
                        seen[results[j].url] = true;
                        unique.push(results[j]);
                    }
                }
                return unique.slice(0, 8);
            })()
        """, tab_id="tab0")

        if js_links:
            print(f"   ✅ Found {len(js_links)} search results via JS:")
            for i, link in enumerate(js_links):
                print(f"   [{i+1}] {link.get('text', '')[:60]}")
                print(f"       {link.get('url', '')[:80]}")
        else:
            print("   ⚠️  JS extraction returned no results")
            js_links = []

        # ── Step 7: Open top results in new tabs ──────────────────
        # Pick top 3-4 results to open in tabs
        urls_to_open = []
        for link in (js_links or result_links)[:4]:
            url = link.get("url") if isinstance(link, dict) else link.get("url", "")
            if url and url not in urls_to_open:
                urls_to_open.append(url)

        if not urls_to_open:
            print("\n⚠️  No URLs found — falling back to known Arroyo Grande dentist URLs for demo")
            urls_to_open = [
                "https://www.google.com/search?q=dentists+in+Arroyo+Grande+CA",
                "https://www.yelp.com/search?find_desc=dentists&find_loc=Arroyo+Grande,+CA",
            ]

        print(f"\n🗂️  Step 6: Opening {len(urls_to_open)} result(s) in new tabs...")
        new_tab_ids = []

        # Create tabs first (without URLs to get IDs fast)
        for i, url in enumerate(urls_to_open):
            tab_id = browser.tab_create(hidden=False)
            new_tab_ids.append(tab_id)
            print(f"   ✅ Created {tab_id}")

        # Navigate all new tabs in parallel using batch!
        print(f"\n⚡ Step 7: Navigating all tabs in parallel (batch op)...")
        url_map = {tid: url for tid, url in zip(new_tab_ids, urls_to_open)}
        nav_results = browser.parallel_navigate(url_map, wait_until="load")

        for tab_id, result in nav_results.items():
            if "error" in result:
                print(f"   ❌ {tab_id}: Error — {result.get('message', 'unknown')}")
            else:
                title = result.get("title", "")[:50]
                url = result.get("url", "")[:60]
                print(f"   ✅ {tab_id}: {title}")
                print(f"       {url}")

        # ── Step 8: Final state ────────────────────────────────────
        print("\n📋 Final tab list:")
        all_tabs = browser.tab_list()
        for t in all_tabs:
            print(f"   • {t['tabId']}: {t.get('title', '')[:50]} — {t.get('url', '')[:60]}")

        # ── Step 9: Take screenshots of each new tab ───────────────
        print(f"\n📸 Step 8: Taking screenshots of all result tabs...")
        screenshots = browser.parallel_screenshots(new_tab_ids, quality=70)
        for tab_id, data in screenshots.items():
            path = f"/tmp/aslan_test_result_{tab_id}.jpg"
            with open(path, "wb") as f:
                f.write(data)
            print(f"   ✅ {tab_id}: {len(data):,} bytes → {path}")

        print("\n" + "=" * 60)
        print("🎉 Manual test complete!")
        print(f"   • Started with 1 tab, now have {len(all_tabs)} tabs open")
        print(f"   • Searched Google for: '{search_query}'")
        print(f"   • Opened {len(new_tab_ids)} results in parallel tabs")
        print(f"   • Screenshots saved to /tmp/aslan_test_*.jpg")
        print("=" * 60)


if __name__ == "__main__":
    main()
