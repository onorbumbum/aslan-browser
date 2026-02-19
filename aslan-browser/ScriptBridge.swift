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
}
