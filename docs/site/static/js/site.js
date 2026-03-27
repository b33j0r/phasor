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
