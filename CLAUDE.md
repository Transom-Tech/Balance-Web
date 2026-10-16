# Balance — notes for coding sessions

Balance is a group-trip expense splitter. Its point: show who's been generous **without shaming anyone** and without telling anyone "it's your turn." It has to work for people who log every receipt nightly and for people who settle once at the end.

Owner: Steve (non-developer; reviews on phone and desktop). Live at https://transom-tech.github.io/Balance-Web/
Feature ideas and bugs are tracked in **GitHub Issues** on this repo.

## How it's built
- **One file:** `index.html` holds all HTML, CSS and JS. No build step, no framework, no npm. GitHub Pages serves `main` directly, so **a merge to main is a deploy**.
- **Backend:** Supabase (auth + Postgres + Storage + realtime), via `@supabase/supabase-js@2` from jsDelivr. The client is `sb`; the URL and publishable key are at the top of the `<script>`.
- **Tables used:** `trips` (incl. `base_currency`, `start_date`, `end_date`, `archived`, `cover_url`), `trip_members` (+ `profiles` join), `expenses` (`amount`, `currency`, `paid_by`, `expense_date`, `emoji`, `split_type`, `receipt_path`), `expense_splits` (`user_id`, `amount_owed`), `trip_invite_codes`, `profiles`.
- **RPCs:** `create_trip_for_user`, `create_expense_for_user`, `insert_expense_splits`, `delete_expense_for_user`, `set_trip_cover`, `set_expense_receipt`. Writes generally go through RPCs; follow that pattern.
- **Realtime:** one channel, `expenses-realtime`, triggers a debounced `loadTripData()`.
- **`fix.html`:** a tiny page that clears a stuck session and sends people back to sign in. Leave it alone.
- **`supabase/`:** SQL that Steve runs by hand in the Supabase SQL Editor. Never assume a schema change exists until he confirms he ran it. If a feature needs one, add a `.sql` file here, make it safe to re-run, and fail with a friendly message when it hasn't been run.

## Helpers and patterns in index.html
`$('id')` is getElementById. `show`/`hide`. `toast(msg,'success'|'error'|'info')`. `openModal`/`closeModal`. `fmt(amount,currency)` puts the minus sign before the symbol (`-$65.00`). `getName(profile)`, `getInitials`, `_esc()` for HTML-escaping user text (use it for anything user-entered that goes into innerHTML). `state` holds `user, trips, currentTripId, members, expenses, splitMode`.

Render flow: `loadTripData()` → `renderAll()` → `renderExpenseForm`, `renderExpenseList`, `renderStats` (also calls `renderHero`), then async `renderBalance()`. `renderBalance` fetches exchange rates, computes paid/owed in the trip currency, and drives **the bubbles, the header stats, the balance list and Settle up**. If you need converted numbers, get them there.

## Product rules (don't break these)
- **No dollar amounts on the main screen** except the expense list. Numbers live in the Balance tab.
- **Bubbles** (`renderBubbles` / `_bubbleTick`): one per member. Level = 0.75 × (paid ÷ that person's own share), where share = the sum of their `expense_splits`, so custom splits count. 75% is "even" (tick mark). Above even: `0.75 + 0.25·0.92·(1 − e^(−2.2·(r−1)))`, which never overflows. When someone's paid total rises, droplets flow from every other bubble into theirs. Respect `prefers-reduced-motion`.
- **Currencies:** expenses are stored in the currency actually spent, so they match receipts. Everything in the Balance tab, the header stats and the bubbles is converted to the **trip's `base_currency`** (`tripCurrency()`, *not* the add-form's currency picker) at the **rate for that expense's date** (Frankfurter/ECB, cached in `_fxCache`). If a rate can't be fetched, show the `#fx-warning` banner. Never silently treat foreign amounts as base currency.
- **Pay-backs:** "Mark as paid" records an expense with description `Settle up: A → B`, paid by A, owed 100% by B, `split_type` custom, emoji 🤝. `isSettleUp(e)` detects them. They count in balances and bubbles but are **excluded** from Total Spent, Per Person and the expense count, and are shown as "Pay-back" in the list.
- **Recalculate** resets equal splits across current members. It must skip pay-backs and `split_type === 'custom'` (otherwise it wipes them out).
- **Cover photo:** shrunk in the browser to ≤1600px JPEG, uploaded to Storage `trip-covers/<trip_id>/cover-<ms>.jpg` (public bucket), then `set_trip_cover()` (which checks membership and the folder). Setup is `supabase/trip-covers.sql`.
- **Accent color:** `--pink`/`--pink2` are overridden per trip with a color picked from the cover photo (`pickAccentFromImage`: most vivid common hue, lightness forced to ~74% so dark text and icons stay readable). It's computed in the browser and cached in localStorage by cover URL, and resets to pink with no cover. Always use `var(--pink)` for accent fills, never the hex.
- **Receipts are private:** shrunk to ≤2000px JPEG and uploaded to the **private** `receipts` bucket at `<trip_id>/<expense_id>-<ms>.jpg`, then `set_expense_receipt()`. They're viewed through 1-hour signed URLs (`createSignedUrl`), never public links. On a new expense, the photo is held in `_pendingReceipt` and uploaded right after the expense is created. In the list, the emoji tile becomes a button with a small badge. Setup is `supabase/receipts.sql`.

## Look and layout
Tokens are in `:root`: navy `#17213d`, pink `#f5a3bf`, background `#f4f2f6`, font Bricolage Grotesque. Pill buttons, 20–28px radii, inline SVG icons (no icon fonts).
- **Phone (≤760px):** one panel at a time, switched by the floating bottom bar (Expenses / + / Balance). Expenses is the default.
- **Desktop:** 761–939px one column; 940–1179px two columns (Expenses wide, Log + Balances stacked); 1180px+ three columns and the banner becomes a rounded card the width of the content.

Check any UI change at 390px, ~900px, ~1100px and 1920px.

## Workflow that has worked
1. Branch off `main`, make the change, open a PR with a plain-English description (Steve reads these).
2. Let Steve try it before it goes live: copy the branch's `index.html` to `preview.html` on `main` (title "Balance (preview)") so it's at `/Balance-Web/preview.html`. It uses **real data**, so warn him about anything that writes (Mark as paid, adding expenses). Delete `preview.html` when the work ships.
3. Steve merges the PR on GitHub himself.

**Testing without real data:** load `index.html` in headless Chromium and intercept the supabase-js URL with a small stub that implements `createClient()` → `auth.getSession`, `onAuthStateChange`, a chainable `from()` builder returning fixture rows, `rpc`, `storage`, and `channel`. That's enough to render every screen and click through flows. Block other network requests, or fulfill Frankfurter with fixed rates to test currency handling.

## Conventions added later
- **Splits:** always build equal splits with `splitEvenly(amount, userIds, payerId)`. It works in whole cents and gives leftover cents to the payer, so splits always sum to the exact amount.
- **User text:** wrap anything user-entered (descriptions, names, trip names, emoji) in `_esc()` before it goes into `innerHTML`. `toast()` sets its message as plain text, so pass plain strings.
