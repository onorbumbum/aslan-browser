"""Unit tests for `aslan shot` argument handling and SDK param building (no browser needed)."""

import argparse

import pytest

from aslan_browser.cli import _build_parser, _shot_target
from aslan_browser.client import _screenshot_params


def parse(*argv: str) -> argparse.Namespace:
    return _build_parser().parse_args(["shot", *argv])


def test_url_and_path_split():
    assert _shot_target(parse("https://example.com", "out.png")) == (
        "https://example.com", "out.png", "png")


def test_path_only_is_current_tab_mode():
    assert _shot_target(parse("out.jpeg")) == (None, "out.jpeg", "jpeg")


def test_url_only_uses_default_jpg_path():
    url, path, fmt = _shot_target(parse("https://example.com"))
    assert (url, path, fmt) == ("https://example.com", "/tmp/aslan-screenshot.jpg", "jpeg")


def test_no_args_uses_default_path():
    assert _shot_target(parse()) == (None, "/tmp/aslan-screenshot.jpg", "jpeg")


def test_extension_is_case_insensitive():
    assert _shot_target(parse("OUT.PNG"))[2] == "png"


def test_unsupported_extension_exits():
    with pytest.raises(SystemExit):
        _shot_target(parse("out.gif"))


def test_extra_positional_exits():
    with pytest.raises(SystemExit):
        _shot_target(parse("https://example.com", "a.png", "b.png"))


def test_full_page_and_height_are_mutually_exclusive():
    with pytest.raises(SystemExit):
        parse("--full-page", "--height", "500")


def test_full_page_with_width_is_allowed():
    args = parse("--full-page", "--width", "1280")
    assert args.full_page and args.width == 1280 and args.height is None


def test_sdk_params_legacy_shape_is_unchanged():
    assert _screenshot_params("tab1", 70, 1440, "jpeg", None, None, False) == {
        "tabId": "tab1", "quality": 70, "width": 1440, "format": "jpeg"}


def test_sdk_params_viewport_and_full_page():
    p = _screenshot_params("tab1", 70, 1440, "png", 1280, None, True)
    assert p["viewportWidth"] == 1280 and p["fullPage"] is True
    assert "viewportHeight" not in p


def test_sdk_rejects_full_page_with_height():
    with pytest.raises(ValueError):
        _screenshot_params("tab1", 70, 1440, "png", 1280, 800, True)


def test_sdk_rejects_unknown_format():
    with pytest.raises(ValueError):
        _screenshot_params("tab1", 70, 1440, "gif", None, None, False)


# ── old-app detection ─────────────────────────────────────────────

import base64

from aslan_browser.client import AslanBrowserError, _screenshot_bytes

_JPEG = base64.b64encode(b"\xff\xd8\xff\xe0legacy").decode()


def test_old_app_result_rejected_when_new_features_requested():
    params = _screenshot_params("tab1", 70, 1440, "png", 1920, None, True)
    with pytest.raises(AslanBrowserError, match="too old"):
        _screenshot_bytes({"data": _JPEG}, params)  # legacy reply: no "format" echo


def test_old_app_result_rejected_for_png_alone():
    params = _screenshot_params("tab1", 70, 1440, "png", None, None, False)
    with pytest.raises(AslanBrowserError):
        _screenshot_bytes({"data": _JPEG}, params)


def test_legacy_request_accepts_legacy_reply():
    params = _screenshot_params("tab1", 70, 1440, "jpeg", None, None, False)
    assert _screenshot_bytes({"data": _JPEG}, params).startswith(b"\xff\xd8")


def test_new_app_result_accepted():
    params = _screenshot_params("tab1", 70, 1440, "png", 1920, None, True)
    result = {"data": _JPEG, "format": "png", "width": 1920, "height": 10657}
    assert _screenshot_bytes(result, params).startswith(b"\xff\xd8")
