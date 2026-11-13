import { test, expect } from "@playwright/test";
import { SessionsPage } from "./pages/sessions-page";

test("Parser branding follows the theme and opens About", async ({ page }) => {
  await page.addInitScript(() => {
    if (!localStorage.getItem("theme")) localStorage.setItem("theme", "light");
  });
  const sessions = new SessionsPage(page);
  await sessions.goto();
  await expect(page).toHaveTitle("Parser");
  const home = page.locator(".header-home");
  await expect(home.getByRole("img", { name: "Parser" })).toHaveClass(/logo-light/);
  await sessions.selectFirstSession();
  await home.click();
  await expect(sessions.analyticsPage).toBeVisible();
  await page.locator("button.version").click();
  const about = page.getByRole("dialog", { name: "Parser", exact: true });
  await expect(about).toBeVisible();
  await expect(about.locator(".about-name")).toHaveText("Parser");
  await expect(about.locator(".about-logo")).toBeVisible();
  await page.keyboard.press("Escape");
  await page.evaluate(() => localStorage.setItem("theme", "dark"));
  await page.reload();
  await expect(home.getByRole("img", { name: "Parser" })).toHaveClass(/logo-dark/);
});

for (const theme of ["light", "dark"]) {
  test(`compact Parser mark keeps header controls separate in ${theme}`, async ({ page }) => {
    await page.addInitScript((theme) => localStorage.setItem("theme", theme), theme);
    await new SessionsPage(page).goto();
    for (const width of [500, 600]) {
      await page.setViewportSize({ width, height: 900 });
      const brand = page.locator(".header-home").getByRole("img", { name: "Parser" });
      await expect(brand).toHaveClass(/header-mark/);
      await expect(brand).toHaveCSS("width", "18px");
      await expect(brand).toHaveCSS("height", "18px");
      const nav = page.locator(".kit-top-bar__nav-select");
      const search = page.locator(".search-hint:visible");
      const sync = page.locator(".sync-btn");
      await expect(nav).toBeVisible();
      await expect(search).toBeVisible();
      await expect(sync).toBeInViewport();
      await expect
        .poll(async () => {
          const boxes = await Promise.all([
            nav.boundingBox(),
            search.boundingBox(),
            sync.boundingBox(),
          ]);
          const [n, s, y] = boxes;
          return !!n && !!s && !!y && n.x + n.width <= s.x && s.x + s.width <= y.x;
        })
        .toBe(true);
    }
  });
}
