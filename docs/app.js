// Interactive catalog preview & OS install switcher for IKEA Browser landing page

const SAMPLE_ITEMS = [
  {
    id: "00275848",
    article: "002.758.48",
    name: "KALLAX",
    type: "Shelving unit",
    variant: "white",
    kind: "Casework",
    ifcClass: "IFCFURNITURE",
    width: 0.415,
    depth: 0.39,
    height: 1.465,
    kb: 50,
    thumb: "assets/thumbs/00275848.jpg",
    url: "https://www.ikea.com/ie/en/p/kallax-shelving-unit-white-00275848/",
  },
  {
    id: "00243800",
    article: "002.438.00",
    name: "HEMNES",
    type: "Bench with shoe storage",
    variant: "white",
    kind: "Furniture",
    ifcClass: "IFCFURNITURE",
    width: 0.85,
    depth: 0.32,
    height: 0.65,
    kb: 49,
    thumb: "assets/thumbs/00243800.jpg",
    url: "https://www.ikea.com/us/en/p/hemnes-bench-with-shoe-storage-white-00243800/",
  },
  {
    id: "00437704",
    article: "004.377.04",
    name: "UPPVIND",
    type: "Table lamp",
    variant: "nickel-plated/white",
    kind: "Lighting",
    ifcClass: "IFCLIGHTFIXTURE",
    width: 0.26,
    depth: 0.26,
    height: 0.47,
    kb: 191,
    thumb: "assets/thumbs/00437704.jpg",
    url: "https://www.ikea.com/eg/en/p/uppvind-table-lamp-nickel-plated-white-00437704/",
  },
  {
    id: "00393352",
    article: "003.933.52",
    name: "VOXNAN",
    type: "Thermostatic shower mixer",
    variant: "chrome-plated",
    kind: "Plumbing",
    ifcClass: "IFCSANITARYTERMINAL",
    width: 0.29,
    depth: 0.13,
    height: null,
    kb: 89,
    thumb: "assets/thumbs/00393352.jpg",
    url: "https://www.ikea.com/se/en/p/voxnan-thermostatic-shower-mixer-chrome-plated-00393352/",
  },
  {
    id: "00211088",
    article: "002.110.88",
    name: "STEFAN",
    type: "Chair",
    variant: "brown-black",
    kind: "Furniture",
    ifcClass: "IFCFURNITURE",
    width: 0.42,
    depth: 0.49,
    height: 0.9,
    kb: 61,
    thumb: "assets/thumbs/00211088.jpg",
    url: "https://www.ikea.com/us/en/p/stefan-chair-brown-black-00211088/",
  },
  {
    id: "00245960",
    article: "002.459.60",
    name: "BESTÅ",
    type: "Frame",
    variant: "black-brown",
    kind: "Casework",
    ifcClass: "IFCFURNITURE",
    width: 0.6,
    depth: 0.2,
    height: 0.64,
    kb: 155,
    thumb: "assets/thumbs/00245960.jpg",
    url: "https://www.ikea.cn/cn/en/p/besta-frame-black-brown-00245960/",
  },
  {
    id: "00298128",
    article: "002.981.28",
    name: "TYSSEDAL",
    type: "Wardrobe",
    variant: "white/mirror glass",
    kind: "Casework",
    ifcClass: "IFCFURNITURE",
    width: 0.88,
    depth: 0.58,
    height: 2.08,
    kb: 199,
    thumb: "assets/thumbs/00298128.jpg",
    url: "https://www.ikea.com/ae/en/p/tyssedal-wardrobe-white-mirror-glass-00298128/",
  },
  {
    id: "00165128",
    article: "001.651.28",
    name: "TÄRNÖ",
    type: "Chair, outdoor",
    variant: "foldable black/light brown",
    kind: "Furniture",
    ifcClass: "IFCFURNITURE",
    width: 0.39,
    depth: 0.4,
    height: 0.79,
    kb: 363,
    thumb: "assets/thumbs/00165128.jpg",
    url: "https://www.ikea.com/au/en/p/taernoe-chair-outdoor-foldable-black-light-brown-stained-00165128/",
  },
];

const OS_CONFIG = {
  windows: {
    assetHint: "constructcraft-v0.14.0-ikea.3-x86_64.msi (or .zip)",
    pluginPath: "%APPDATA%\\ConstructCAD\\data\\plugins\\ikea_browser\\",
  },
  macos: {
    assetHint: "constructcraft-v0.14.0-ikea.3-aarch64-apple-darwin.dmg (Apple Silicon) or x86_64-apple-darwin.dmg",
    pluginPath: "~/Library/Application Support/ConstructCAD/plugins/ikea_browser/",
  },
  linux: {
    assetHint: "constructcraft-v0.14.0-ikea.3-x86_64.AppImage (or .deb / .tar.gz)",
    pluginPath: "~/.local/share/ConstructCAD/plugins/ikea_browser/",
  },
};

let activeKind = "All";
let searchQuery = "";
let selectedId = SAMPLE_ITEMS[0].id;

function formatDim(val) {
  return val != null ? `${val.toFixed(2)} m` : "—";
}

function formatDimensions(item) {
  const parts = [];
  if (item.width != null) parts.push(`W ${item.width.toFixed(2)} m`);
  if (item.depth != null) parts.push(`D ${item.depth.toFixed(2)} m`);
  if (item.height != null) parts.push(`H ${item.height.toFixed(2)} m`);
  return parts.join(" × ");
}

function renderCatalog() {
  const grid = document.getElementById("catalog-grid");
  if (!grid) return;

  const q = searchQuery.trim().toLowerCase();
  const filtered = SAMPLE_ITEMS.filter((item) => {
    const kindMatch = activeKind === "All" || item.kind === activeKind;
    const textMatch =
      !q ||
      item.name.toLowerCase().includes(q) ||
      item.type.toLowerCase().includes(q) ||
      item.variant.toLowerCase().includes(q) ||
      item.article.includes(q) ||
      item.id.includes(q);
    return kindMatch && textMatch;
  });

  if (filtered.length === 0) {
    grid.innerHTML = `<div class="catalog-empty">No matching sample items. Try clearing your filter or searching for "KALLAX" or "002.758.48".</div>`;
    return;
  }

  if (!filtered.some((item) => item.id === selectedId)) {
    selectedId = filtered[0].id;
  }

  grid.innerHTML = filtered
    .map(
      (item) => `
      <button
        type="button"
        class="item-card${item.id === selectedId ? " is-selected" : ""}"
        data-item-id="${item.id}"
        aria-pressed="${item.id === selectedId}"
      >
        <div class="item-thumb">
          <img src="${item.thumb}" alt="${item.name} — ${item.type}" />
        </div>
        <div class="item-name">${item.name}</div>
        <div class="item-sub">${item.type}</div>
        <div class="item-meta-row">
          <span>${item.article}</span>
          <span>${item.kind}</span>
        </div>
      </button>
    `
    )
    .join("");

  grid.querySelectorAll(".item-card").forEach((card) => {
    card.addEventListener("click", () => {
      selectedId = card.dataset.itemId;
      grid.querySelectorAll(".item-card").forEach((c) => {
        const isSel = c.dataset.itemId === selectedId;
        c.classList.toggle("is-selected", isSel);
        c.setAttribute("aria-pressed", String(isSel));
      });
      renderInspector();
    });
  });

  renderInspector();
}

function renderInspector() {
  const item = SAMPLE_ITEMS.find((i) => i.id === selectedId) || SAMPLE_ITEMS[0];
  if (!item) return;

  document.getElementById("insp-name").textContent = item.name;
  document.getElementById("insp-subtitle").textContent = `${item.type} — ${item.variant}`;
  document.getElementById("insp-article").textContent = item.article;

  const img = document.getElementById("insp-img");
  img.src = item.thumb;
  img.alt = `${item.name} ${item.type}`;

  document.getElementById("insp-kind").textContent = item.kind;
  document.getElementById("insp-ifc").textContent = item.ifcClass;
  document.getElementById("insp-dims").textContent = formatDimensions(item);
  document.getElementById("insp-size").textContent = `${item.kb} KB (Draco GLB)`;

  const link = document.getElementById("insp-url");
  link.href = item.url;
}

function initPreview() {
  const filterBtns = document.querySelectorAll(".filter-btn");
  filterBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      activeKind = btn.dataset.kind;
      filterBtns.forEach((b) => b.classList.toggle("is-active", b === btn));
      renderCatalog();
    });
  });

  const searchInput = document.getElementById("preview-search");
  if (searchInput) {
    searchInput.addEventListener("input", (e) => {
      searchQuery = e.target.value;
      renderCatalog();
    });
  }

  renderCatalog();
}

function initOsTabs() {
  const tabs = document.querySelectorAll(".os-tab");
  const assetEl = document.getElementById("os-asset-hint");
  const pathEl = document.getElementById("os-plugin-path");
  const copyBtn = document.getElementById("copy-path-btn");

  const setOs = (os) => {
    const cfg = OS_CONFIG[os] || OS_CONFIG.windows;
    tabs.forEach((t) => t.classList.toggle("is-active", t.dataset.os === os));
    if (assetEl) assetEl.textContent = cfg.assetHint;
    if (pathEl) pathEl.textContent = cfg.pluginPath;
  };

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => setOs(tab.dataset.os));
  });

  // Detect visitor OS as default
  const ua = navigator.userAgent.toLowerCase();
  if (ua.includes("mac")) setOs("macos");
  else if (ua.includes("linux")) setOs("linux");
  else setOs("windows");

  if (copyBtn && pathEl) {
    copyBtn.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(pathEl.textContent);
        const orig = copyBtn.textContent;
        copyBtn.textContent = "Copied";
        setTimeout(() => {
          copyBtn.textContent = orig;
        }, 1600);
      } catch {
        // Fallback ignored if clipboard permission denied
      }
    });
  }
}

function initReveal() {
  const els = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window)) {
    els.forEach((el) => el.classList.add("is-visible"));
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12 }
  );
  els.forEach((el) => io.observe(el));
}

document.addEventListener("DOMContentLoaded", () => {
  initPreview();
  initOsTabs();
  initReveal();
});
