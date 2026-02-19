#!/usr/bin/env python3
"""
Gmail Login Test — aslan-browser real-world demo
=================================================
Launches aslan-browser with a VISIBLE window, navigates to Gmail login,
and walks you through the login flow using the accessibility tree.

Usage:
    1. Make sure aslan-browser is NOT already running
    2. Run: python3 gmail_login_test.py
    3. Watch the browser window and follow prompts in the terminal
"""

import os
import subprocess
import sys
import time

from aslan_browser import AslanBrowser, AslanBrowserError

SOCKET_PATH = "/tmp/aslan-browser.sock"
APP_PATH = "/Applications/aslan-browser.app/Contents/MacOS/aslan-browser"


def launch_browser():
    """Launch aslan-browser in visible mode."""
    # Clean up
    subprocess.run(["pkill", "-f", "aslan-browser"], capture_output=True)
    time.sleep(0.5)
    if os.path.exists(SOCKET_PATH):
        os.remove(SOCKET_PATH)

    print("🦁 Launching aslan-browser (visible window)...")
    proc = subprocess.Popen(
        [APP_PATH],  # No --hidden flag = visible window
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Wait for socket
    for _ in range(20):
        if os.path.exists(SOCKET_PATH):
            print("✅ Browser ready!\n")
            return proc
        time.sleep(0.25)

    print("❌ Timed out waiting for browser socket")
    proc.kill()
    sys.exit(1)


def print_tree(tree, max_nodes=20):
    """Pretty-print the accessibility tree."""
    for i, node in enumerate(tree[:max_nodes]):
        ref = node.get("ref", "?")
        role = node.get("role", "?")
        name = node.get("name", "")[:60]
        value = node.get("value", "")
        extra = f' value="{value}"' if value else ""
        print(f"  {ref:8s} {role:14s} \"{name}\"{extra}")
    if len(tree) > max_nodes:
        print(f"  ... and {len(tree) - max_nodes} more nodes")


def find_by_role_and_hint(tree, role, hints):
    """Find a node by role and name hint keywords."""
    for node in tree:
        if node.get("role") == role:
            name = (node.get("name", "") + " " + node.get("value", "")).lower()
            if any(h.lower() in name for h in hints):
                return node
    return None


def find_by_role(tree, role):
    """Find all nodes with a given role."""
    return [n for n in tree if n.get("role") == role]


def wait_and_get_tree(browser, delay=1.5):
    """Wait a moment then get the a11y tree."""
    time.sleep(delay)
    return browser.get_accessibility_tree()


def main():
    proc = launch_browser()

    try:
        with AslanBrowser() as browser:
            # ── Step 1: Navigate to Gmail ────────────────────
            print("=" * 60)
            print("STEP 1: Navigating to Gmail login...")
            print("=" * 60)
            browser.navigate(
                "https://accounts.google.com/signin/v2/identifier?service=mail&flowName=GlifWebSignIn",
                wait_until="load",
                timeout=30000,
            )
            time.sleep(2)

            url = browser.get_url()
            title = browser.get_title()
            print(f"  URL:   {url}")
            print(f"  Title: {title}")

            # Take a screenshot
            browser.save_screenshot("/tmp/gmail-step1.jpg", quality=80)
            print("  📸 Screenshot: /tmp/gmail-step1.jpg\n")

            # ── Step 2: Show the accessibility tree ──────────
            print("=" * 60)
            print("STEP 2: Accessibility tree of login page")
            print("=" * 60)
            tree = wait_and_get_tree(browser, delay=2)
            print_tree(tree, max_nodes=30)
            print()

            # ── Step 3: Find email field and fill it ─────────
            print("=" * 60)
            print("STEP 3: Enter email address")
            print("=" * 60)

            # Try to find the email input
            email_field = find_by_role_and_hint(tree, "textbox", ["email", "phone", "mail", "e-post"])
            if not email_field:
                # Try just finding any textbox
                textboxes = find_by_role(tree, "textbox")
                if textboxes:
                    email_field = textboxes[0]

            if email_field:
                print(f"  Found email field: {email_field['ref']} \"{email_field.get('name', '')}\"")
            else:
                print("  ⚠️  Could not auto-detect email field.")
                print("  Current tree refs with 'textbox' role: none found")
                print("  You may need to pick a ref from the tree above.")

            email = input("\n  Enter your Gmail address: ").strip()
            if not email:
                print("  No email entered, exiting.")
                return

            if email_field:
                target = email_field["ref"]
            else:
                target = input("  Enter the ref to use (e.g. @e5): ").strip()

            print(f"  Filling {target} with '{email}'...")
            browser.click(target)
            time.sleep(0.3)
            browser.fill(target, email)
            time.sleep(0.5)

            # Screenshot after filling
            browser.save_screenshot("/tmp/gmail-step3.jpg", quality=80)
            print("  📸 Screenshot: /tmp/gmail-step3.jpg\n")

            # ── Step 4: Click "Next" ─────────────────────────
            print("=" * 60)
            print("STEP 4: Click 'Next' button")
            print("=" * 60)
            tree = wait_and_get_tree(browser, delay=0.5)

            next_btn = find_by_role_and_hint(tree, "button", ["next", "weiter", "sonraki", "ileri", "devam"])
            if not next_btn:
                # Sometimes it's just "Next" as a generic button
                buttons = find_by_role(tree, "button")
                print("  Available buttons:")
                for b in buttons:
                    print(f"    {b['ref']:8s} \"{b.get('name', '')}\"")
                ref = input("  Enter the ref for 'Next' button: ").strip()
            else:
                ref = next_btn["ref"]
                print(f"  Found 'Next' button: {ref} \"{next_btn.get('name', '')}\"")

            print(f"  Clicking {ref}...")
            browser.click(ref)

            # Wait for password page to load
            print("  Waiting for password page...")
            time.sleep(3)

            browser.save_screenshot("/tmp/gmail-step4.jpg", quality=80)
            print("  📸 Screenshot: /tmp/gmail-step4.jpg\n")

            # ── Step 5: Enter password ───────────────────────
            print("=" * 60)
            print("STEP 5: Enter password")
            print("=" * 60)
            tree = wait_and_get_tree(browser, delay=1)
            print("  Current tree:")
            print_tree(tree, max_nodes=30)
            print()

            pw_field = find_by_role_and_hint(tree, "textbox", ["password", "parola", "şifre", "kennwort"])
            if not pw_field:
                # Password fields sometimes have a different role
                for node in tree:
                    name = node.get("name", "").lower()
                    if "password" in name or "parola" in name or "şifre" in name:
                        pw_field = node
                        break

            if pw_field:
                print(f"  Found password field: {pw_field['ref']} \"{pw_field.get('name', '')}\"")
                target = pw_field["ref"]
            else:
                print("  ⚠️  Could not auto-detect password field.")
                target = input("  Enter the ref for password field: ").strip()

            password = input("  Enter your password (hidden in tree, not logged): ").strip()
            if not password:
                print("  No password entered, exiting.")
                return

            print(f"  Filling {target}...")
            browser.click(target)
            time.sleep(0.3)
            browser.fill(target, password)
            time.sleep(0.5)

            browser.save_screenshot("/tmp/gmail-step5.jpg", quality=80)
            print("  📸 Screenshot: /tmp/gmail-step5.jpg\n")

            # ── Step 6: Click "Next" again ───────────────────
            print("=" * 60)
            print("STEP 6: Click 'Next' to submit password")
            print("=" * 60)
            tree = wait_and_get_tree(browser, delay=0.5)

            next_btn = find_by_role_and_hint(tree, "button", ["next", "weiter", "sonraki", "ileri", "devam"])
            if not next_btn:
                buttons = find_by_role(tree, "button")
                print("  Available buttons:")
                for b in buttons:
                    print(f"    {b['ref']:8s} \"{b.get('name', '')}\"")
                ref = input("  Enter the ref for 'Next' button: ").strip()
            else:
                ref = next_btn["ref"]
                print(f"  Found 'Next' button: {ref} \"{next_btn.get('name', '')}\"")

            print(f"  Clicking {ref}...")
            browser.click(ref)

            # ── Step 7: Handle 2FA / wait for inbox ──────────
            print()
            print("=" * 60)
            print("STEP 7: Post-login (2FA, inbox, etc.)")
            print("=" * 60)
            print("  Waiting for page to settle...")
            time.sleep(5)

            url = browser.get_url()
            title = browser.get_title()
            print(f"  URL:   {url}")
            print(f"  Title: {title}")

            browser.save_screenshot("/tmp/gmail-step7.jpg", quality=80)
            print("  📸 Screenshot: /tmp/gmail-step7.jpg\n")

            if "myaccount" in url or "mail.google" in url or "inbox" in title.lower():
                print("  🎉 LOGIN SUCCESSFUL!")
            elif "challenge" in url or "signin" in url:
                print("  🔐 Looks like 2FA or a challenge is required.")
                print("  You can complete it in the visible browser window.")
                print("  The browser will stay open — press Enter when done.")
                input("  Press Enter to continue...")

                time.sleep(2)
                url = browser.get_url()
                title = browser.get_title()
                print(f"  URL:   {url}")
                print(f"  Title: {title}")
                browser.save_screenshot("/tmp/gmail-final.jpg", quality=80)
                print("  📸 Screenshot: /tmp/gmail-final.jpg")
            else:
                print(f"  Current state unclear. Check the browser window.")
                print("  Press Enter to take a final screenshot and exit.")
                input()
                browser.save_screenshot("/tmp/gmail-final.jpg", quality=80)

            # ── Final: show inbox tree ───────────────────────
            print()
            print("=" * 60)
            print("FINAL: Accessibility tree of current page")
            print("=" * 60)
            tree = wait_and_get_tree(browser, delay=1)
            print_tree(tree, max_nodes=40)

            print()
            print("=" * 60)
            print("✅ Gmail login test complete!")
            print("=" * 60)
            print()
            print("Screenshots saved to /tmp/gmail-step*.jpg")
            print("Browser window is still open. Press Enter to quit.")
            input()

    except KeyboardInterrupt:
        print("\n\nInterrupted.")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        print("Shutting down browser...")
        proc.terminate()
        proc.wait(timeout=5)
        print("Done.")


if __name__ == "__main__":
    main()
