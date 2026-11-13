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
