// MacMD reader runtime: renders code, math and diagrams, keeps scroll position in sync
// with the editor, and reports back to the app through window.webkit.messageHandlers.macmd.
(() => {
  "use strict";

  const post = (message) => window.webkit?.messageHandlers?.macmd?.postMessage(message);
  const prefersDark = () => window.matchMedia("(prefers-color-scheme: dark)").matches;

  function highlightCode() {
    if (!window.hljs) return;
    for (const block of document.querySelectorAll('pre code[class*="language-"]')) {
      const language = block.className.match(/language-(\S+)/)?.[1];
      if (language && hljs.getLanguage(language)) hljs.highlightElement(block);
    }
  }

  function renderMath() {
    if (!window.katex) return;
    for (const element of document.querySelectorAll(".math[data-tex]")) {
      katex.render(element.dataset.tex, element, {
        displayMode: element.classList.contains("display"),
        throwOnError: false,
        output: "htmlAndMathml",
      });
    }
  }

  /// A page color token as an opaque `rgb()` composited over the paper, so Mermaid gets a color it can shade.
  /// WebKit serializes computed colors as `rgb(…)` or `color(srgb …)`; painting them onto a canvas
  /// resolves either form (and any alpha) without parsing.
  function opaque(variable, canvas) {
    const resolve = (value) => {
      const probe = document.createElement("span");
      probe.style.color = value;
      document.body.append(probe);
      const color = getComputedStyle(probe).color;
      probe.remove();
      return color;
    };
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.globalCompositeOperation = "copy";
    context.fillStyle = resolve("var(--paper)");
    context.fillRect(0, 0, 1, 1);
    context.globalCompositeOperation = "source-over";
    context.fillStyle = resolve(`var(${variable})`);
    context.fillRect(0, 0, 1, 1);
    const [r, g, b] = context.getImageData(0, 0, 1, 1).data;
    return `rgb(${r}, ${g}, ${b})`;
  }

  /// Mermaid's `base` theme, fed from the page's tokens so diagrams read as part of the page.
  function diagramTheme() {
    const canvas = Object.assign(document.createElement("canvas"), { width: 1, height: 1 });
    const color = (variable) => opaque(variable, canvas);
    const paper = color("--paper");
    const ink = color("--ink");
    const muted = color("--ink-muted");
    const faint = color("--ink-faint");
    const surface = color("--surface");
    const surface2 = color("--surface-2");
    return {
      darkMode: prefersDark(),
      background: paper,
      fontFamily: "system-ui, -apple-system, sans-serif",
      fontSize: "14px",
      textColor: ink,
      primaryColor: surface,
      primaryTextColor: ink,
      primaryBorderColor: faint,
      secondaryColor: surface2,
      secondaryTextColor: ink,
      secondaryBorderColor: faint,
      tertiaryColor: paper,
      tertiaryTextColor: ink,
      tertiaryBorderColor: faint,
      mainBkg: surface,
      nodeBorder: faint,
      nodeTextColor: ink,
      clusterBkg: surface2,
      clusterBorder: faint,
      titleColor: ink,
      lineColor: muted,
      edgeLabelBackground: paper,
      actorBkg: surface,
      actorBorder: faint,
      actorTextColor: ink,
      actorLineColor: faint,
      signalColor: muted,
      signalTextColor: ink,
      labelBoxBkgColor: surface,
      labelBoxBorderColor: faint,
      labelTextColor: ink,
      loopTextColor: ink,
      noteBkgColor: surface2,
      noteBorderColor: faint,
      noteTextColor: ink,
      activationBkgColor: surface2,
      activationBorderColor: faint,
      useGradient: false,
      dropShadow: "none",
    };
  }

  async function renderDiagrams() {
    const nodes = [...document.querySelectorAll(".mermaid")];
    if (!window.mermaid || nodes.length === 0) return;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "base",
      fontFamily: "system-ui, -apple-system, sans-serif",
      themeVariables: diagramTheme(),
      sequence: { actorFontSize: 14, messageFontSize: 14, noteFontSize: 14 },
    });
    for (const node of nodes) {
      // Keep the source so the diagram can be drawn again with other colors.
      node.dataset.source ??= node.textContent;
      node.removeAttribute("data-processed");
      node.classList.remove("error");
      node.textContent = node.dataset.source;
      try {
        await mermaid.run({ nodes: [node] });
      } catch (error) {
        node.classList.add("error");
        node.textContent = `Diagram error: ${error?.message ?? error}`;
      }
    }
  }

  // Diagrams bake their colors in: redraw them when the system switches between light and dark.
  // Redraws queue behind the one in progress so two never interleave.
  let diagrams = Promise.resolve();
  const drawDiagrams = () => (diagrams = diagrams.then(renderDiagrams, renderDiagrams));
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => drawDiagrams());

  function markMissingImages() {
    for (const image of document.images) {
      image.addEventListener("error", () => {
        image.replaceWith(Object.assign(document.createElement("span"), {
          className: "missing img",
          textContent: `Image not found: ${image.getAttribute("src")}`,
        }));
      }, { once: true });
    }
  }

  const blocks = () => document.querySelectorAll(".markdown-body [data-line]");

  function topLine() {
    for (const block of blocks()) {
      if (block.getBoundingClientRect().bottom > 8) return Number(block.dataset.line);
    }
    return 1;
  }

  const reportTopLine = () => post({ type: "topLine", line: topLine() });

  let scrollScheduled = false;
  window.addEventListener("scroll", () => {
    if (scrollScheduled) return;
    scrollScheduled = true;
    requestAnimationFrame(() => {
      scrollScheduled = false;
      reportTopLine();
    });
  }, { passive: true });

  window.macmd = {
    scrollToLine(line) {
      let target = null;
      for (const block of blocks()) {
        if (Number(block.dataset.line) <= line) target = block;
        else break;
      }
      if (line <= 1 || !target) window.scrollTo(0, 0);
      else window.scrollTo(0, target.getBoundingClientRect().top + window.scrollY - 24);
      // A jump to where the page already is fires no scroll event: report the line regardless.
      reportTopLine();
    },
    scrollToAnchor(id) {
      document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
      reportTopLine();
    },
    exportDocument() {
      const root = document.documentElement.cloneNode(true);
      root.querySelectorAll("script").forEach((script) => script.remove());
      // Exported files open outside MacMD: drop event handlers and script links from the document.
      root.querySelectorAll("*").forEach((element) => {
        for (const attribute of [...element.attributes]) {
          const value = attribute.value.trim().toLowerCase();
          if (attribute.name.toLowerCase().startsWith("on") || value.startsWith("javascript:")) {
            element.removeAttribute(attribute.name);
          }
        }
      });
      return "<!doctype html>\n" + root.outerHTML;
    },
  };

  async function render() {
    markMissingImages();
    highlightCode();
    renderMath();
    await drawDiagrams();
    reportTopLine();
    post({ type: "rendered" });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", render, { once: true });
  } else {
    render();
  }
})();
