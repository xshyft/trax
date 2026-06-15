/* SoulForge wiki — Docsify config + plugins. Browser-only: never modifies the .md sources.
 * - resolves [[wikilinks]] and [[slug|alias]] to real links
 * - strips YAML frontmatter, surfacing `related:` as a clickable footer
 * - renders ```mermaid``` code fences to diagrams, with per-diagram source toggle + SVG/PNG export
 * The markdown files keep their frontmatter, [[links]], and raw mermaid source intact, so any
 * agent reading the wiki sees the full, structured content. */
(function () {
  // Docsify scrolls to anchors via document.querySelector('#' + id). A heading id that starts with
  // a DIGIT (e.g. "5-schema--control-plane" from "## 5. Schema …") is an INVALID CSS selector, so
  // querySelector throws SyntaxError — which aborts Docsify's render pipeline before doneEach runs,
  // so diagrams never render. Fall back to getElementById (no leading-digit restriction) for a
  // single "#id" selector. Patch installed before Docsify loads.
  var _qs = Document.prototype.querySelector;
  Document.prototype.querySelector = function (sel) {
    try { return _qs.call(this, sel); }
    catch (e) {
      var m = (typeof sel === "string") && sel.match(/^#([^\s.#>:\[]+)$/);
      if (m && this.getElementById) { return this.getElementById(m[1]); }
      throw e;
    }
  };

  var SF_ARCH = ["platform-overview", "orchestrator", "data-model", "execution-model", "serving", "v1",
    "discovery", "soul-forger", "chamber-portal", "weight-registry", "authsvc", "impl-slice-v0-1",
    "athanor-portal"];
  function sfPath(slug) { slug = slug.trim(); return (SF_ARCH.indexOf(slug) >= 0 ? "/architecture/" : "/concepts/") + slug + ".md"; }
  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  var SF_TRAIL_KEY = "sf_wiki_nav_trail_v1";

  window.$docsify = {
    name: "SoulForge Wiki",
    homepage: "index.md",
    relativePath: true,
    subMaxLevel: 3,
    search: "auto",
    markdown: {
      renderer: {
        code: function (code, lang) {
          if (lang === "mermaid") {
            return '<div class="sf-mermaid">' +
                     '<div class="sf-bar">' +
                       '<button class="sf-toggle" type="button">&lt;/&gt; source</button>' +
                       '<button class="sf-ascii-btn" type="button" style="display:none">&#x25a4; ASCII</button>' +
                       '<button class="sf-zoom" type="button">&#x2922; zoom</button>' +
                       '<button class="sf-svg" type="button">&#x2913; SVG</button>' +
                       '<button class="sf-png" type="button">&#x2913; PNG</button>' +
                     '</div>' +
                     '<div class="mermaid">' + code + '</div>' +
                     '<pre class="sf-src" style="display:none"><code>' + esc(code) + '</code></pre>' +
                   '</div>';
          }
          if (lang === "ascii") {
            // ASCII fallback that follows a mermaid block; hidden until toggled.
            return '<div class="sf-ascii" style="display:none"><pre><code>' + esc(code) + '</code></pre></div>';
          }
          // Everything else: Prism-highlighted (via origin.code) wrapped with a top bar that
          // shows the language on the LEFT and a Copy button on the RIGHT. The raw source is
          // stashed in a hidden <textarea> so Copy yields the exact text, not the highlighted HTML.
          var html = this.origin.code.apply(this, arguments);
          var label = (lang || "text");
          return '<div class="sf-code">' +
                   '<div class="sf-code-bar">' +
                     '<span class="sf-code-lang">' + esc(label) + '</span>' +
                     '<button class="sf-copy" type="button">Copy</button>' +
                   '</div>' +
                   html +
                   '<textarea class="sf-code-raw" hidden>' + esc(code) + '</textarea>' +
                 '</div>';
        }
      }
    },
    plugins: [
      function (hook) {
        hook.beforeEach(function (content) {
          var footer = "";
          var fm = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
          if (fm) {
            var rel = fm[1].match(/related:\s*\[([^\]]*)\]/);
            if (rel && rel[1].trim()) {
              footer = "\n\n---\n\n**Related:** " + rel[1].split(",")
                .map(function (s) { return s.trim(); }).filter(Boolean)
                .map(function (s) { return "[" + s.charAt(0).toUpperCase() + s.slice(1) + "](" + sfPath(s) + ")"; }).join(" · ") + "\n";
            }
          }
          return content
            .replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "")
            .replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, function (_, s, a) { return "[" + a + "](" + sfPath(s) + ")"; })
            .replace(/\[\[([^\]]+)\]\]/g, function (_, s) { return "[" + s + "](" + sfPath(s) + ")"; })
            + footer;
        });
        hook.doneEach(function () { sfRenderMermaid(); sfWireCode(); sfWireTasks(); sfRenderNavTrail(); });
      }
    ]
  };

  // Wire each fenced code block's Copy button (idempotent — runs on every route render).
  function sfWireCode() {
    document.querySelectorAll(".sf-code:not([data-wired])").forEach(function (box) {
      box.setAttribute("data-wired", "1");
      var btn = box.querySelector(".sf-copy");
      var raw = box.querySelector(".sf-code-raw");
      if (!btn || !raw) return;
      btn.addEventListener("click", function () {
        var text = raw.value;
        var done = function () {
          btn.classList.add("ok"); btn.textContent = "Copied";
          setTimeout(function () { btn.classList.remove("ok"); btn.textContent = "Copy"; }, 1200);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, function () { sfCopyFallback(text); done(); });
        } else { sfCopyFallback(text); done(); }
      });
    });
  }
  function sfCopyFallback(text) {
    var t = document.createElement("textarea");
    t.value = text; t.style.position = "fixed"; t.style.opacity = "0";
    document.body.appendChild(t); t.select();
    try { document.execCommand("copy"); } catch (e) {}
    t.remove();
  }

  // Style markdown task-list checkboxes — purely READ-ONLY. They stay Docsify's disabled inputs
  // (the markdown `[ ]` / `[x]` is the source of truth, changed only in the doc). We just reflect
  // that state: mark completed items (for strike-through) and show a per-list progress chip.
  function sfWireTasks() {
    document.querySelectorAll(".markdown-section li.task-list-item").forEach(function (li) {
      var cb = li.querySelector("input[type=checkbox]");
      if (cb) li.classList.toggle("sf-done", cb.checked);   // input stays disabled / read-only
    });
    sfUpdateProgress();
  }
  // A small "done/total" chip above each TOP-LEVEL task list (nested sub-lists are skipped).
  function sfUpdateProgress() {
    document.querySelectorAll(".markdown-section ul.task-list").forEach(function (ul) {
      if (ul.parentElement && ul.parentElement.closest && ul.parentElement.closest("li.task-list-item")) return; // nested
      var items = ul.querySelectorAll(":scope > li.task-list-item");
      if (items.length < 2) return;
      var done = 0;
      items.forEach(function (li) { var c = li.querySelector("input[type=checkbox]"); if (c && c.checked) done++; });
      var chip = ul.previousElementSibling;
      if (!chip || !chip.classList || !chip.classList.contains("sf-progress")) {
        chip = document.createElement("div"); chip.className = "sf-progress"; ul.parentNode.insertBefore(chip, ul);
      }
      chip.textContent = done + " / " + items.length + " done";
      chip.classList.toggle("done", done === items.length);
    });
  }

  function sfRenderMermaid() {
    if (!window.mermaid) return;
    // CLAIM nodes synchronously first. doneEach can fire again while a render is still in-flight
    // (mermaid sets data-processed only AFTER it finishes); without a synchronous claim, the second
    // pass grabs the same not-yet-processed node and runs mermaid on it concurrently → corruption
    // ("renders, then breaks"). data-sf-claimed is set now, before any async work.
    var nodes = Array.prototype.slice.call(
      document.querySelectorAll(".sf-mermaid .mermaid:not([data-sf-claimed])"));
    nodes.forEach(function (n) { n.setAttribute("data-sf-claimed", "1"); });
    var i = 0;
    function afterAll() {
      document.querySelectorAll(".sf-mermaid").forEach(sfWire);
      sfScrollToAnchor();   // diagrams changed the page height — re-scroll to the ?id= target
    }
    // Render ONE claimed node at a time (next() runs only after the previous resolves) — also
    // isolates a parse error to its own diagram (its source just stays visible).
    function next() {
      if (i >= nodes.length) { afterAll(); return; }
      var node = nodes[i++];
      var p;
      try { p = mermaid.run({ nodes: [node] }); } catch (e) { next(); return; }
      if (p && typeof p.then === "function") { p.then(next, next); } else { next(); }
    }
    next();
  }

  // Docsify scrolls to ?id=… right after markdown render; mermaid renders later and shifts the
  // layout, so re-scroll once diagrams are in. Also retried shortly after, since SVG layout settles.
  function sfScrollToAnchor() {
    var m = location.hash.match(/[?&]id=([^&]+)/);
    if (!m) return;
    var id = decodeURIComponent(m[1]);
    var el = document.getElementById(id);
    if (el) { el.scrollIntoView(); setTimeout(function () { var e2 = document.getElementById(id); if (e2) e2.scrollIntoView(); }, 150); }
  }

  function sfWire(box) {
    if (box.getAttribute("data-wired")) return;
    box.setAttribute("data-wired", "1");
    var diagram = box.querySelector(".mermaid");
    var src = box.querySelector(".sf-src");
    var bToggle = box.querySelector(".sf-toggle");
    var bAscii = box.querySelector(".sf-ascii-btn");
    var bZoom = box.querySelector(".sf-zoom");
    var bSvg = box.querySelector(".sf-svg");
    var bPng = box.querySelector(".sf-png");

    // An `ascii` code fence right after the mermaid block is its ASCII fallback.
    var ascii = box.nextElementSibling;
    if (ascii && ascii.classList && ascii.classList.contains("sf-ascii")) {
      box.appendChild(ascii);                 // move it inside the box
      if (bAscii) bAscii.style.display = "";
    } else {
      ascii = null;
    }

    function showOnly(which) {                // which: 'diagram' | 'src' | 'ascii'
      diagram.style.display = which === "diagram" ? "block" : "none";
      if (src) src.style.display = which === "src" ? "block" : "none";
      if (ascii) ascii.style.display = which === "ascii" ? "block" : "none";
      if (bToggle) bToggle.innerHTML = which === "src" ? "&#x25a6; diagram" : "&lt;/&gt; source";
      if (bAscii) bAscii.innerHTML = which === "ascii" ? "&#x25a6; diagram" : "&#x25a4; ASCII";
    }

    if (bToggle) bToggle.addEventListener("click", function () {
      showOnly(src && src.style.display === "none" ? "src" : "diagram");
    });
    if (bAscii) bAscii.addEventListener("click", function () {
      showOnly(ascii && ascii.style.display === "none" ? "ascii" : "diagram");
    });
    if (bZoom) bZoom.addEventListener("click", function () { sfZoom(box); });
    // Clicking the rendered diagram itself enters zoom mode.
    if (diagram) {
      diagram.style.cursor = "zoom-in";
      diagram.addEventListener("click", function () { if (diagram.querySelector("svg")) sfZoom(box); });
    }
    if (bSvg) bSvg.addEventListener("click", function () {
      var svg = box.querySelector("svg"); if (!svg) return;
      var data = new XMLSerializer().serializeToString(svg);
      sfDownload(new Blob([data], { type: "image/svg+xml;charset=utf-8" }), "diagram.svg");
    });
    if (bPng) bPng.addEventListener("click", function () {
      var svg = box.querySelector("svg"); if (!svg) return;
      var rect = svg.getBoundingClientRect();
      var w = Math.max(1, rect.width || 800), h = Math.max(1, rect.height || 600);
      var data = new XMLSerializer().serializeToString(svg);
      var img = new Image();
      img.onload = function () {
        var c = document.createElement("canvas");
        c.width = w * 2; c.height = h * 2;
        var ctx = c.getContext("2d"); ctx.scale(2, 2);
        ctx.fillStyle = "#0f1117"; ctx.fillRect(0, 0, w, h);
        ctx.drawImage(img, 0, 0, w, h);
        c.toBlob(function (b) { if (b) sfDownload(b, "diagram.png"); });
      };
      img.src = "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(data)));
    });
  }

  function sfZoom(box) {
    var svg = box.querySelector("svg"); if (!svg) return;
    var ov = document.createElement("div"); ov.className = "sf-overlay";
    var stage = document.createElement("div"); stage.className = "sf-overlay-stage";
    var inner = document.createElement("div"); inner.className = "sf-overlay-inner";
    inner.innerHTML = new XMLSerializer().serializeToString(svg);
    stage.appendChild(inner);
    // Mermaid stamps an inline `max-width:Npx` on the svg that caps it small. Strip it and let the
    // clone fill the overlay so it opens at full size (then wheel/buttons zoom further).
    var zsvg = inner.querySelector("svg");
    if (zsvg) { zsvg.removeAttribute("width"); zsvg.removeAttribute("height");
      zsvg.style.maxWidth = "none"; zsvg.style.width = "92vw"; zsvg.style.height = "auto"; }
    var close = document.createElement("button"); close.className = "sf-overlay-close";
    close.type = "button"; close.innerHTML = "&times;"; close.title = "Close (Esc)";
    var ctrls = document.createElement("div"); ctrls.className = "sf-overlay-ctrls";
    ctrls.innerHTML = '<button type="button" data-z="in" title="Zoom in">+</button>' +
                      '<button type="button" data-z="out" title="Zoom out">&minus;</button>' +
                      '<button type="button" data-z="reset" title="Reset">&#x21bb;</button>';
    var hint = document.createElement("div"); hint.className = "sf-overlay-hint";
    hint.textContent = "scroll to zoom · drag to pan · Esc to close";
    ov.appendChild(stage); ov.appendChild(close); ov.appendChild(ctrls); ov.appendChild(hint);

    var scale = 1, tx = 0, ty = 0, dragging = false, moved = false, sx = 0, sy = 0;
    var BASE_VW = 92;
    // Zoom by resizing the SVG itself (vector re-render → always crisp); transform is pan-only.
    // CSS transform:scale on a promoted layer rasterizes the svg once then scales the bitmap → blur.
    function apply() {
      if (zsvg) zsvg.style.width = (BASE_VW * scale) + "vw";
      inner.style.transform = "translate(" + tx + "px," + ty + "px)";
    }
    function zoom(factor) { scale = Math.min(12, Math.max(0.2, scale * factor)); apply(); }

    stage.addEventListener("wheel", function (e) {
      e.preventDefault();
      zoom(e.deltaY < 0 ? 1.15 : 1 / 1.15);
    }, { passive: false });
    stage.addEventListener("mousedown", function (e) {
      dragging = true; moved = false; sx = e.clientX - tx; sy = e.clientY - ty;
      stage.classList.add("grabbing");
    });
    function onMove(e) { if (!dragging) return; moved = true; tx = e.clientX - sx; ty = e.clientY - sy; apply(); }
    function onUp() { dragging = false; stage.classList.remove("grabbing"); }
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
    ctrls.addEventListener("click", function (e) {
      var z = e.target && e.target.getAttribute && e.target.getAttribute("data-z");
      if (z === "in") zoom(1.3); else if (z === "out") zoom(1 / 1.3);
      else if (z === "reset") { scale = 1; tx = 0; ty = 0; apply(); }
    });

    function done() {
      ov.remove();
      document.removeEventListener("keydown", onkey);
      window.removeEventListener("mousemove", onMove);
      window.removeEventListener("mouseup", onUp);
    }
    function onkey(e) { if (e.key === "Escape") done(); }
    close.addEventListener("click", done);
    document.addEventListener("keydown", onkey);
    document.body.appendChild(ov);
    apply();
  }

  function sfDownload(blob, name) {
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  }

  function sfCurrentRoute() {
    var h = location.hash || "";
    var m = h.match(/^#\/([^?]+)/);
    var route = m ? ("/" + m[1]) : "/index.md";
    if (route === "/") route = "/index.md";
    return route;
  }

  function sfCurrentTitle() {
    var h1 = document.querySelector(".markdown-section h1");
    if (h1 && h1.textContent && h1.textContent.trim()) return h1.textContent.trim();
    var route = sfCurrentRoute();
    var leaf = route.split("/").pop() || "index.md";
    return leaf.replace(/\.md$/, "").replace(/[-_]+/g, " ");
  }

  function sfLoadTrail() {
    try {
      var raw = sessionStorage.getItem(SF_TRAIL_KEY);
      var parsed = raw ? JSON.parse(raw) : [];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  function sfSaveTrail(trail) {
    try { sessionStorage.setItem(SF_TRAIL_KEY, JSON.stringify(trail)); } catch (e) {}
  }

  function sfUpdateTrail() {
    var route = sfCurrentRoute();
    var title = sfCurrentTitle();
    var trail = sfLoadTrail();
    var idx = -1;
    for (var i = 0; i < trail.length; i++) {
      if (trail[i] && trail[i].route === route) { idx = i; break; }
    }
    if (idx >= 0) {
      trail = trail.slice(0, idx + 1);
      trail[idx].title = title;
    } else {
      trail.push({ route: route, title: title });
    }
    if (trail.length > 12) trail = trail.slice(trail.length - 12);
    sfSaveTrail(trail);
    return trail;
  }

  function sfRenderNavTrail() {
    var host = document.querySelector(".content");
    var section = document.querySelector(".markdown-section");
    if (!host || !section) return;

    var nav = document.querySelector(".sf-navtrail");
    if (!nav) {
      nav = document.createElement("div");
      nav.className = "sf-navtrail";
      host.insertBefore(nav, section);
    } else if (nav.nextSibling !== section) {
      host.insertBefore(nav, section);
    }

    var trail = sfUpdateTrail();
    var current = sfCurrentRoute();
    var prev = trail.length > 1 ? trail[trail.length - 2] : null;

    var html = '<button class="sf-back" type="button"' + (prev ? "" : " disabled") + '>Back</button>';
    html += '<nav class="sf-crumbs" aria-label="Breadcrumb">';
    for (var i = 0; i < trail.length; i++) {
      var item = trail[i];
      var active = item.route === current;
      if (i > 0) html += '<span class="sf-sep">/</span>';
      if (active) {
        html += '<span class="sf-crumb current">' + esc(item.title) + '</span>';
      } else {
        html += '<a class="sf-crumb" href="#' + item.route + '">' + esc(item.title) + '</a>';
      }
    }
    html += '</nav>';
    nav.innerHTML = html;

    var back = nav.querySelector(".sf-back");
    if (back && prev) {
      back.addEventListener("click", function () {
        location.hash = "#" + prev.route;
      });
    }
  }

  // Initialize mermaid once (it's loaded before this script).
  if (window.mermaid) {
    try { mermaid.initialize({ startOnLoad: false, theme: "dark", securityLevel: "loose" }); } catch (e) {}
  }
})();
