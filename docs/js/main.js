/**
 * Progressive enhancements for the marketing site: a collapsible nav on narrow
 * viewports, the hero climb path drawing itself, and a scroll-triggered reveal
 * for each section. All three degrade to a fully readable page when scripting
 * is unavailable.
 */

const REVEAL_SELECTOR = ".spotlight, .grid-section, .specs, .cta";

/** Wires the header's menu button to show and hide the primary nav. */
function setUpNavToggle() {
  const toggle = document.querySelector(".nav-toggle");
  const nav = document.querySelector(".site-nav");
  if (!toggle || !nav) return;

  toggle.addEventListener("click", () => {
    const opening = toggle.getAttribute("aria-expanded") !== "true";
    toggle.setAttribute("aria-expanded", String(opening));
    nav.dataset.open = String(opening);
  });

  nav.addEventListener("click", (event) => {
    if (event.target.closest("a")) closeNav(toggle, nav);
  });
}

/** Returns the nav to its collapsed state, matching the toggle's ARIA state. */
function closeNav(toggle, nav) {
  toggle.setAttribute("aria-expanded", "false");
  nav.dataset.open = "false";
}

/**
 * Publishes the climb path's measured length so the draw animation covers it
 * exactly. Without this the CSS falls back to an estimate, which either clips
 * the line or leaves it hanging.
 */
function measureClimbPath() {
  const path = document.querySelector(".climb-profile__path");
  if (!path) return;
  path.style.setProperty("--path-length", path.getTotalLength());
}

/** Fades each section in as it scrolls into view, unless motion is unwelcome. */
function setUpScrollReveal() {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const observer = new IntersectionObserver(revealIntersectingSections, {
    rootMargin: "0px 0px -10% 0px",
  });

  for (const section of document.querySelectorAll(REVEAL_SELECTOR)) {
    section.classList.add("js-reveal");
    section.dataset.revealed = "false";
    observer.observe(section);
  }
}

/** Marks sections revealed once seen, and stops watching them. */
function revealIntersectingSections(entries, observer) {
  for (const entry of entries) {
    if (!entry.isIntersecting) continue;
    entry.target.dataset.revealed = "true";
    observer.unobserve(entry.target);
  }
}

setUpNavToggle();
measureClimbPath();
setUpScrollReveal();
