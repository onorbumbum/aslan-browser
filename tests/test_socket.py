#!/usr/bin/env python3
"""
Integration test for aslan-browser JSON-RPC socket server.
The app must be running before executing this script.

Usage:
    python3 tests/test_socket.py
"""

import json
import socket
import sys
import time
import base64

SOCKET_PATH = "/tmp/aslan-browser.sock"
TIMEOUT = 15  # seconds per request


def send_rpc(sock, method, params=None, req_id=1):
    """Send a JSON-RPC request and return the parsed response."""
    request = {"jsonrpc": "2.0", "id": req_id, "method": method}
    if params is not None:
        request["params"] = params

    msg = json.dumps(request) + "\n"
    sock.sendall(msg.encode("utf-8"))

    # Read response (newline-delimited)
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Socket closed before response received")
        buf += chunk

    line = buf.split(b"\n")[0]
    return json.loads(line)


def send_raw(sock, raw_bytes):
    """Send raw bytes and return the parsed response."""
    sock.sendall(raw_bytes)

    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Socket closed before response received")
        buf += chunk

    line = buf.split(b"\n")[0]
    return json.loads(line)


def connect():
    """Connect to the Unix socket."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(TIMEOUT)
    sock.connect(SOCKET_PATH)
    return sock


def test_navigate():
    """Test: navigate to example.com"""
    print("TEST: navigate ... ", end="", flush=True)
    sock = connect()
    try:
        resp = send_rpc(sock, "navigate", {"url": "https://example.com"})
        assert "result" in resp, f"Expected result, got: {resp}"
        assert "url" in resp["result"], f"Missing url in result: {resp}"
        assert "example.com" in resp["result"]["url"], f"Unexpected URL: {resp['result']['url']}"
        print(f"OK — {resp['result']['url']}")
    finally:
        sock.close()


def test_get_title():
    """Test: getTitle after navigation"""
    print("TEST: getTitle ... ", end="", flush=True)
    sock = connect()
    try:
        # Navigate first
        send_rpc(sock, "navigate", {"url": "https://example.com"}, req_id=1)
        time.sleep(0.5)

        resp = send_rpc(sock, "getTitle", req_id=2)
        assert "result" in resp, f"Expected result, got: {resp}"
        assert "title" in resp["result"], f"Missing title in result: {resp}"
        print(f"OK — \"{resp['result']['title']}\"")
    finally:
        sock.close()


def test_get_url():
    """Test: getURL after navigation"""
    print("TEST: getURL ... ", end="", flush=True)
    sock = connect()
    try:
        send_rpc(sock, "navigate", {"url": "https://example.com"}, req_id=1)
        resp = send_rpc(sock, "getURL", req_id=2)
        assert "result" in resp, f"Expected result, got: {resp}"
        assert "url" in resp["result"], f"Missing url in result: {resp}"
        assert "example.com" in resp["result"]["url"], f"Unexpected URL: {resp['result']['url']}"
        print(f"OK — {resp['result']['url']}")
    finally:
        sock.close()


def test_evaluate():
    """Test: evaluate JavaScript"""
    print("TEST: evaluate ... ", end="", flush=True)
    sock = connect()
    try:
        send_rpc(sock, "navigate", {"url": "https://example.com"}, req_id=1)
        time.sleep(0.5)

        resp = send_rpc(sock, "evaluate", {"script": "return document.title"}, req_id=2)
        assert "result" in resp, f"Expected result, got: {resp}"
        assert "value" in resp["result"], f"Missing value in result: {resp}"
        print(f"OK — \"{resp['result']['value']}\"")
    finally:
        sock.close()


def test_screenshot():
    """Test: screenshot returns base64 JPEG"""
    print("TEST: screenshot ... ", end="", flush=True)
    sock = connect()
    try:
        send_rpc(sock, "navigate", {"url": "https://example.com"}, req_id=1)
        time.sleep(1)

        # Use larger recv buffer for screenshot data
        request = {"jsonrpc": "2.0", "id": 2, "method": "screenshot", "params": {"quality": 50, "width": 800}}
        msg = json.dumps(request) + "\n"
        sock.sendall(msg.encode("utf-8"))

        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                raise ConnectionError("Socket closed")
            buf += chunk

        line = buf.split(b"\n")[0]
        resp = json.loads(line)

        assert "result" in resp, f"Expected result, got: {resp}"
        assert "data" in resp["result"], f"Missing data in result: {resp}"

        # Verify it's valid base64
        decoded = base64.b64decode(resp["result"]["data"])
        assert len(decoded) > 100, f"Screenshot too small: {len(decoded)} bytes"
        # JPEG starts with FF D8
        assert decoded[:2] == b"\xff\xd8", "Not a valid JPEG"
        print(f"OK — {len(decoded)} bytes JPEG")
    finally:
        sock.close()


def test_invalid_method():
    """Test: unknown method returns error"""
    print("TEST: invalid method ... ", end="", flush=True)
    sock = connect()
    try:
        resp = send_rpc(sock, "nonexistent_method")
        assert "error" in resp, f"Expected error, got: {resp}"
        assert resp["error"]["code"] == -32601, f"Expected -32601, got: {resp['error']['code']}"
        print(f"OK — code {resp['error']['code']}")
    finally:
        sock.close()


def test_malformed_json():
    """Test: malformed JSON returns parse error"""
    print("TEST: malformed JSON ... ", end="", flush=True)
    sock = connect()
    try:
        resp = send_raw(sock, b"this is not json\n")
        assert "error" in resp, f"Expected error, got: {resp}"
        assert resp["error"]["code"] == -32700, f"Expected -32700, got: {resp['error']['code']}"
        print(f"OK — code {resp['error']['code']}")
    finally:
        sock.close()


def test_missing_params():
    """Test: navigate without url returns invalid params error"""
    print("TEST: missing params ... ", end="", flush=True)
    sock = connect()
    try:
        resp = send_rpc(sock, "navigate", {})
        assert "error" in resp, f"Expected error, got: {resp}"
        assert resp["error"]["code"] == -32602, f"Expected -32602, got: {resp['error']['code']}"
        print(f"OK — code {resp['error']['code']}")
    finally:
        sock.close()


def main():
    print(f"Connecting to {SOCKET_PATH}")
    print(f"{'=' * 50}")

    tests = [
        test_navigate,
        test_get_title,
        test_get_url,
        test_evaluate,
        test_screenshot,
        test_invalid_method,
        test_malformed_json,
        test_missing_params,
    ]

    passed = 0
    failed = 0
    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            failed += 1
            print(f"FAIL — {e}")

    print(f"{'=' * 50}")
    print(f"Results: {passed} passed, {failed} failed, {len(tests)} total")

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
