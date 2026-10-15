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

  async function renderDiagrams() {
    const nodes = [...document.querySelectorAll(".mermaid")];
    if (!window.mermaid || nodes.length === 0) return;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: prefersDark() ? "dark" : "neutral",
      fontFamily: getComputedStyle(document.documentElement).getPropertyValue("--font-body"),
    });
    for (const node of nodes) {
      try {
        await mermaid.run({ nodes: [node] });
      } catch (error) {
        node.classList.add("error");
        node.textContent = `Diagram error: ${error?.message ?? error}`;
      }
    }
  }

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

  let scrollScheduled = false;
  window.addEventListener("scroll", () => {
    if (scrollScheduled) return;
    scrollScheduled = true;
    requestAnimationFrame(() => {
      scrollScheduled = false;
      post({ type: "topLine", line: topLine() });
    });
  }, { passive: true });

  window.macmd = {
    scrollToLine(line) {
      let target = null;
      for (const block of blocks()) {
        if (Number(block.dataset.line) <= line) target = block;
        else break;
      }
      if (line <= 1 || !target) return window.scrollTo(0, 0);
      window.scrollTo(0, target.getBoundingClientRect().top + window.scrollY - 24);
    },
    scrollToAnchor(id) {
      document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
    },
    exportDocument() {
      const root = document.documentElement.cloneNode(true);
      root.querySelectorAll("script").forEach((script) => script.remove());
      return "<!doctype html>\n" + root.outerHTML;
    },
  };

  async function render() {
    markMissingImages();
    highlightCode();
    renderMath();
    await renderDiagrams();
    post({ type: "rendered" });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", render, { once: true });
  } else {
    render();
  }
})();
