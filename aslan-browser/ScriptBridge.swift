//
//  ScriptBridge.swift
//  aslan-browser
//

import WebKit

enum ScriptBridge {

    static var injectedJS: String {
        """
        (function() {
            "use strict";

            if (window.__agent) return;

            window.__agent = {};

            // --- Post helper ---

            window.__agent.post = function(type, data) {
                try {
                    var msg = { type: type };
                    if (data) {
                        Object.keys(data).forEach(function(k) { msg[k] = data[k]; });
                    }
                    window.webkit.messageHandlers.agent.postMessage(msg);
                } catch (e) {
                    // Message handler not available — silently ignore
                }
            };

            // --- Network tracking ---

            (function() {
                var pending = 0;
                var wasIdle = true;

                function increment() {
                    pending++;
                    if (wasIdle) {
                        wasIdle = false;
                        window.__agent.post("networkBusy", { pending: pending });
                    }
                }

                function decrement() {
                    pending = Math.max(0, pending - 1);
                    if (pending === 0 && !wasIdle) {
                        wasIdle = true;
                        window.__agent.post("networkIdle");
                    }
                }

                // Monkey-patch fetch
                var originalFetch = window.fetch;
                window.fetch = function() {
                    increment();
                    return originalFetch.apply(this, arguments)
                        .then(function(response) {
                            decrement();
                            return response;
                        })
                        .catch(function(err) {
                            decrement();
                            throw err;
                        });
                };

                // Monkey-patch XMLHttpRequest
                var originalXHROpen = XMLHttpRequest.prototype.open;
                var originalXHRSend = XMLHttpRequest.prototype.send;

                XMLHttpRequest.prototype.open = function() {
                    this.__agentTracked = true;
                    return originalXHROpen.apply(this, arguments);
                };

                XMLHttpRequest.prototype.send = function() {
                    if (this.__agentTracked) {
                        increment();
                        var xhr = this;
                        var done = false;
                        function onDone() {
                            if (!done) {
                                done = true;
                                decrement();
                            }
                        }
                        xhr.addEventListener("load", onDone);
                        xhr.addEventListener("error", onDone);
                        xhr.addEventListener("abort", onDone);
                        xhr.addEventListener("timeout", onDone);
                    }
                    return originalXHRSend.apply(this, arguments);
                };

                window.__agent._networkPending = function() { return pending; };
            })();

            // --- DOM stability ---

            (function() {
                var timer = null;
                var domQuietMs = 500;
                var observer = null;

                window.__agent.startDOMObserver = function(quietMs) {
                    if (quietMs !== undefined) domQuietMs = quietMs;

                    if (observer) {
                        observer.disconnect();
                    }

                    function resetTimer() {
                        if (timer) clearTimeout(timer);
                        timer = setTimeout(function() {
                            window.__agent.post("domStable");
                        }, domQuietMs);
                    }

                    observer = new MutationObserver(function() {
                        resetTimer();
                    });

                    if (document.body) {
                        observer.observe(document.body, {
                            childList: true,
                            subtree: true,
                            attributes: true
                        });
                    }

                    // Start the initial timer — if DOM is already stable,
                    // it will fire after quietMs with no mutations
                    resetTimer();
                };

                // Auto-start DOM observer
                window.__agent.startDOMObserver();
            })();

            // --- Accessibility tree extraction ---

            (function() {

                // Role inference map: tag (+ input type) → ARIA role
                var ROLE_MAP = {
                    "A": "link",
                    "BUTTON": "button",
                    "SELECT": "combobox",
                    "TEXTAREA": "textbox",
                    "IMG": "img",
                    "H1": "heading", "H2": "heading", "H3": "heading",
                    "H4": "heading", "H5": "heading", "H6": "heading",
                    "NAV": "navigation",
                    "MAIN": "main",
                    "HEADER": "banner",
                    "FOOTER": "contentinfo",
                    "ASIDE": "complementary",
                    "FORM": "form",
                    "TABLE": "table",
                    "UL": "list",
                    "OL": "list",
                    "LI": "listitem"
                };

                var INPUT_TYPE_ROLES = {
                    "text": "textbox",
                    "email": "textbox",
                    "password": "textbox",
                    "search": "textbox",
                    "tel": "textbox",
                    "url": "textbox",
                    "number": "textbox",
                    "checkbox": "checkbox",
                    "radio": "radio",
                    "submit": "button",
                    "button": "button",
                    "reset": "button"
                };

                // Tags that are always included (interactive or semantic)
                var INTERACTIVE_TAGS = {
                    "A": true, "BUTTON": true, "INPUT": true,
                    "SELECT": true, "TEXTAREA": true
                };

                var LANDMARK_TAGS = {
                    "NAV": true, "MAIN": true, "HEADER": true,
                    "FOOTER": true, "ASIDE": true, "FORM": true
                };

                var SEMANTIC_TAGS = {
                    "H1": true, "H2": true, "H3": true,
                    "H4": true, "H5": true, "H6": true,
                    "IMG": true, "TABLE": true,
                    "UL": true, "OL": true, "LI": true
                };

                function getRole(el) {
                    // Explicit role attribute takes priority
                    var explicitRole = el.getAttribute("role");
                    if (explicitRole) return explicitRole;

                    var tag = el.tagName;

                    if (tag === "INPUT") {
                        var inputType = (el.getAttribute("type") || "text").toLowerCase();
                        return INPUT_TYPE_ROLES[inputType] || null;
                    }

                    return ROLE_MAP[tag] || null;
                }

                function isHidden(el) {
                    // aria-hidden
                    if (el.getAttribute("aria-hidden") === "true") return true;

                    var style = window.getComputedStyle(el);
                    if (style.display === "none") return true;
                    if (style.visibility === "hidden") return true;

                    // Zero bounding rect
                    var rect = el.getBoundingClientRect();
                    if (rect.width === 0 && rect.height === 0) return true;

                    return false;
                }

                function shouldInclude(el) {
                    var tag = el.tagName;

                    // Always include interactive elements
                    if (INTERACTIVE_TAGS[tag]) return true;

                    // Include landmarks
                    if (LANDMARK_TAGS[tag]) return true;

                    // Include semantic elements
                    if (SEMANTIC_TAGS[tag]) return true;

                    // Include any element with explicit role attribute
                    if (el.hasAttribute("role")) return true;

                    return false;
                }

                function resolveName(el) {
                    // 1. aria-label
                    var ariaLabel = el.getAttribute("aria-label");
                    if (ariaLabel) return ariaLabel.trim();

                    // 2. aria-labelledby
                    var labelledBy = el.getAttribute("aria-labelledby");
                    if (labelledBy) {
                        var ids = labelledBy.split(/\\s+/);
                        var parts = [];
                        for (var i = 0; i < ids.length; i++) {
                            var ref = document.getElementById(ids[i]);
                            if (ref) parts.push(ref.textContent.trim());
                        }
                        var joined = parts.join(" ").trim();
                        if (joined) return joined;
                    }

                    // 3. Associated <label>
                    if (el.id) {
                        var label = document.querySelector('label[for="' + CSS.escape(el.id) + '"]');
                        if (label) {
                            var labelText = label.textContent.trim();
                            if (labelText) return labelText;
                        }
                    }
                    // Parent <label>
                    var parentLabel = el.closest("label");
                    if (parentLabel) {
                        var parentText = parentLabel.textContent.trim();
                        if (parentText) return parentText;
                    }

                    // 4. placeholder
                    var placeholder = el.getAttribute("placeholder");
                    if (placeholder) return placeholder.trim();

                    // 5. title
                    var titleAttr = el.getAttribute("title");
                    if (titleAttr) return titleAttr.trim();

                    // 6. Visible textContent (truncated to 80 chars, whitespace-collapsed)
                    var text = (el.textContent || "").replace(/\\s+/g, " ").trim();
                    if (text.length > 80) text = text.substring(0, 80);
                    return text;
                }

                function getRect(el) {
                    var r = el.getBoundingClientRect();
                    return {
                        x: Math.round(r.x * 100) / 100,
                        y: Math.round(r.y * 100) / 100,
                        w: Math.round(r.width * 100) / 100,
                        h: Math.round(r.height * 100) / 100
                    };
                }

                function getValue(el) {
                    var tag = el.tagName;
                    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") {
                        return el.value || "";
                    }
                    return undefined;
                }

                window.__agent.extractA11yTree = function() {
                    var nodes = [];
                    var refIndex = 0;

                    // Remove old refs
                    var oldRefs = document.querySelectorAll("[data-agent-ref]");
                    for (var i = 0; i < oldRefs.length; i++) {
                        oldRefs[i].removeAttribute("data-agent-ref");
                    }

                    // TreeWalker for efficient DOM traversal
                    var walker = document.createTreeWalker(
                        document.body || document.documentElement,
                        NodeFilter.SHOW_ELEMENT,
                        null
                    );

                    var el = walker.currentNode;
                    while (el) {
                        if (el.nodeType === Node.ELEMENT_NODE && shouldInclude(el) && !isHidden(el)) {
                            var role = getRole(el);
                            if (role) {
                                var ref = "@e" + refIndex;
                                el.setAttribute("data-agent-ref", ref);

                                var node = {
                                    ref: ref,
                                    role: role,
                                    name: resolveName(el),
                                    tag: el.tagName
                                };

                                var val = getValue(el);
                                if (val !== undefined) {
                                    node.value = val;
                                }

                                node.rect = getRect(el);

                                nodes.push(node);
                                refIndex++;
                            }
                        }
                        el = walker.nextNode();
                    }

                    return nodes;
                };
            })();

            // --- Console capture ---

            (function() {
                ["log", "warn", "error", "info"].forEach(function(level) {
                    var original = console[level];
                    console[level] = function() {
                        var args = Array.prototype.slice.call(arguments);
                        var message = args.map(function(a) {
                            return typeof a === "object" ? JSON.stringify(a) : String(a);
                        }).join(" ");
                        window.__agent.post("console", { level: level, message: message });
                        original.apply(console, args);
                    };
                });
            })();

            // --- JS error capture ---

            window.onerror = function(message, source, lineno) {
                window.__agent.post("error", {
                    message: String(message),
                    source: source || "",
                    line: lineno || 0
                });
            };

            window.addEventListener("unhandledrejection", function(event) {
                window.__agent.post("error", {
                    message: String(event.reason),
                    source: "",
                    line: 0
                });
            });

            // --- waitForSelector ---

            window.__agent.waitForSelector = function(selector, timeoutMs) {
                timeoutMs = timeoutMs || 5000;
                return new Promise(function(resolve, reject) {
                    // Check if already present
                    var el = document.querySelector(selector);
                    if (el) {
                        resolve(true);
                        return;
                    }

                    var observer = null;
                    var timer = null;

                    function cleanup() {
                        if (observer) observer.disconnect();
                        if (timer) clearTimeout(timer);
                    }

                    observer = new MutationObserver(function() {
                        var el = document.querySelector(selector);
                        if (el) {
                            cleanup();
                            resolve(true);
                        }
                    });

                    observer.observe(document.documentElement, {
                        childList: true,
                        subtree: true,
                        attributes: true
                    });

                    timer = setTimeout(function() {
                        cleanup();
                        reject(new Error("waitForSelector timed out after " + timeoutMs + "ms: " + selector));
                    }, timeoutMs);
                });
            };
        })();
        """
    }

    static func makeUserScript() -> WKUserScript {
        WKUserScript(
            source: injectedJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }

    // MARK: - Learn Mode JS

    static var learnModeJS: String {
        """
        (function() {
            "use strict";
            if (window.__agentLearn) return;
            window.__agentLearn = {};

            function buildComposedPath(event) {
                var path = event.composedPath();
                var segments = [];
                var currentSegment = [];

                for (var i = 0; i < path.length; i++) {
                    var node = path[i];
                    if (node === window || node === document) break;

                    if (node.nodeType === 11) {
                        // ShadowRoot — finalize current segment and start new one
                        if (currentSegment.length > 0) {
                            segments.push(currentSegment.join(" > "));
                        }
                        currentSegment = [];
                        continue;
                    }

                    if (node.nodeType !== 1) continue; // Skip non-element nodes

                    var desc = node.tagName || "";
                    if (node.id) desc += "#" + node.id;
                    if (node.className && typeof node.className === "string") {
                        var classes = node.className.trim().split(/\\s+/).slice(0, 3).join(".");
                        if (classes) desc += "." + classes;
                    }
                    currentSegment.push(desc);
                }

                if (currentSegment.length > 0) {
                    segments.push(currentSegment.join(" > "));
                }

                // Reverse so outermost is first, prefix shadow segments
                segments.reverse();
                for (var s = 1; s < segments.length; s++) {
                    segments[s] = "#shadow-root > " + segments[s];
                }

                return segments;
            }

            function buildTargetInfo(event) {
                var el = event.target;
                if (!el || !el.tagName) return {};

                var attrs = {};
                var attrNames = ["id", "class", "name", "type", "role", "aria-label",
                    "aria-labelledby", "data-testid", "placeholder", "href", "src",
                    "action", "value", "contenteditable"];
                for (var a = 0; a < attrNames.length; a++) {
                    var val = el.getAttribute(attrNames[a]);
                    if (val !== null && val !== "") attrs[attrNames[a]] = val;
                }

                var text = (el.textContent || "").replace(/\\s+/g, " ").trim();
                if (text.length > 80) text = text.substring(0, 80);

                var rect = el.getBoundingClientRect();

                return {
                    tagName: el.tagName,
                    textContent: text,
                    attributes: attrs,
                    composedPath: buildComposedPath(event),
                    rect: {
                        x: Math.round(rect.x),
                        y: Math.round(rect.y),
                        w: Math.round(rect.width),
                        h: Math.round(rect.height)
                    }
                };
            }

            // --- Click listener ---
            window.__agentLearn.onClick = function(event) {
                var target = buildTargetInfo(event);
                window.__agent.post("learn.action", {
                    actionType: "click",
                    url: window.location.href,
                    pageTitle: document.title,
                    target: target,
                    clientX: event.clientX,
                    clientY: event.clientY,
                    button: event.button
                });
            };

            // --- Input listener (debounced) ---
            var inputTimer = null;
            window.__agentLearn.onInput = function(event) {
                // Capture target info synchronously (composedPath only available during dispatch)
                var target = buildTargetInfo(event);
                var val = event.target.value !== undefined ? event.target.value : (event.target.textContent || "");
                if (inputTimer) clearTimeout(inputTimer);
                inputTimer = setTimeout(function() {
                    window.__agent.post("learn.action", {
                        actionType: "input",
                        url: window.location.href,
                        pageTitle: document.title,
                        target: target,
                        value: val
                    });
                }, 300);
            };

            // --- Keydown listener (filtered) ---
            window.__agentLearn.onKeydown = function(event) {
                var dominated = ["Enter", "Tab", "Escape", "Backspace", "Delete"];
                var isSpecial = dominated.indexOf(event.key) !== -1;
                var hasModifier = event.ctrlKey || event.metaKey || event.altKey;
                if (!isSpecial && !hasModifier) return;

                var target = buildTargetInfo(event);
                window.__agent.post("learn.action", {
                    actionType: "keydown",
                    url: window.location.href,
                    pageTitle: document.title,
                    target: target,
                    key: event.key,
                    code: event.code,
                    ctrlKey: event.ctrlKey,
                    shiftKey: event.shiftKey,
                    altKey: event.altKey,
                    metaKey: event.metaKey
                });
            };

            // --- Scroll listener (debounced) ---
            var scrollTimer = null;
            window.__agentLearn.onScroll = function() {
                if (scrollTimer) clearTimeout(scrollTimer);
                scrollTimer = setTimeout(function() {
                    window.__agent.post("learn.action", {
                        actionType: "scroll",
                        url: window.location.href,
                        pageTitle: document.title,
                        scrollX: window.scrollX,
                        scrollY: window.scrollY
                    });
                }, 500);
            };

            // Register all listeners
            document.addEventListener("click", window.__agentLearn.onClick, {capture: true, passive: true});
            document.addEventListener("input", window.__agentLearn.onInput, {capture: true, passive: true});
            document.addEventListener("keydown", window.__agentLearn.onKeydown, {capture: true, passive: true});
            document.addEventListener("scroll", window.__agentLearn.onScroll, {capture: true, passive: true});
        })();
        """
    }

    static var learnModeCleanupJS: String {
        """
        (function() {
            if (!window.__agentLearn) return;
            document.removeEventListener("click", window.__agentLearn.onClick, true);
            document.removeEventListener("input", window.__agentLearn.onInput, true);
            document.removeEventListener("keydown", window.__agentLearn.onKeydown, true);
            document.removeEventListener("scroll", window.__agentLearn.onScroll, true);
            delete window.__agentLearn;
        })();
        """
    }
}
