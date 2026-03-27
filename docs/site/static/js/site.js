const THEME_STORAGE_KEY = "phasor-docs-theme";
const DEFAULT_THEME = "sunset-wave-dark";

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  const select = document.querySelector("[data-theme-select]");
  if (select && select.value !== theme) {
    select.value = theme;
  }
}

function initializeThemePicker() {
  const select = document.querySelector("[data-theme-select]");
  const storedTheme = localStorage.getItem(THEME_STORAGE_KEY) || DEFAULT_THEME;
  applyTheme(storedTheme);

  if (!select) {
    return;
  }

  select.addEventListener("change", () => {
    const theme = select.value || DEFAULT_THEME;
    localStorage.setItem(THEME_STORAGE_KEY, theme);
    applyTheme(theme);
  });
}

function activateSourcePane(browser, targetId) {
  const files = browser.querySelectorAll(".source-file");
  const panes = browser.querySelectorAll(".source-pane");

  for (const file of files) {
    file.classList.toggle("is-active", file.dataset.sourceTarget === targetId);
  }

  for (const pane of panes) {
    pane.classList.toggle("is-active", pane.dataset.sourcePane === targetId);
  }
}

initializeThemePicker();

for (const browser of document.querySelectorAll("[data-source-browser]")) {
  const files = browser.querySelectorAll(".source-file");
  if (files.length === 0) {
    continue;
  }

  for (const file of files) {
    file.addEventListener("click", () => {
      activateSourcePane(browser, file.dataset.sourceTarget ?? "");
    });
  }

  const initialTarget = browser.querySelector(".source-file.is-active")?.dataset.sourceTarget
    ?? files[0].dataset.sourceTarget
    ?? "";
  activateSourcePane(browser, initialTarget);
}
