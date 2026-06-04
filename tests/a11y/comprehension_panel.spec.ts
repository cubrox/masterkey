import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { seedAndLogin } from "./fixtures/seed";

/**
 * Comprehension questions-panel accessibility (A11Y-5 #126).
 *
 * COMP-4 (#124) added an interactive answer UI (labeled textareas +
 * <details> reveals) to the questions panel, but the panel lazy-loads
 * via an Anthropic call that CI can't make — so reading_surface.spec
 * only ever sees the panel's "unavailable" state.
 *
 * Here we seed the comprehension cache (`withQuestions`) so the panel
 * is a cache HIT and renders the real answer UI with no Anthropic call,
 * then axe-scan it. Gate matches the rest of the harness: zero
 * serious/critical under WCAG 2.0 A+AA.
 */
test("comprehension answer panel a11y", async ({ page, context, request }) => {
  const { passageId } = await seedAndLogin(request, context, "default", {
    withQuestions: true,
  });

  await page.goto(`/read/${passageId}`);
  await expect(page.locator("#reading-surface")).toBeVisible();

  // The panel lazy-loads (hx-trigger="load delay:200ms") then swaps in
  // the questions fragment. Wait for the real answer UI before scanning.
  await expect(page.getByText("Reveal answer").first()).toBeVisible();

  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa"])
    .analyze();

  const blockers = results.violations.filter(
    (v) => v.impact === "critical" || v.impact === "serious",
  );
  if (blockers.length > 0) {
    console.log("[a11y blockers — questions panel]", JSON.stringify(blockers, null, 2));
  }
  const nonBlocking = results.violations.filter(
    (v) => v.impact !== "critical" && v.impact !== "serious",
  );
  if (nonBlocking.length > 0) {
    console.log(
      "[a11y non-blocking — questions panel]",
      nonBlocking.map((v) => `${v.id} (${v.impact})`).join(", "),
    );
  }

  expect(blockers, "axe found serious/critical violations on the questions panel").toHaveLength(0);
});
