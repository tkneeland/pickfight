# PickFight website

One static page: `site/index.html` (inline CSS, no scripts, Google Fonts only). Screenshots live in `site/img/` (resized copies of `docs/launch/screenshots/`, so relative paths survive a move to a custom domain).

Preview: https://tkneeland.github.io/pickfight/site/ (GitHub Pages already serves the repo's main branch root). Locally, open `site/index.html` in a browser.

## 1. Mailing list (Kit)

The decision on #729 is Kit as the mailing provider.

1. Create a free Kit account at kit.com and a new **Form** (Grow > Landing Pages & Forms > Form, inline).
2. Open the form's embed settings and copy its numeric ID (it appears in the form URL and embed code, as in `https://app.kit.com/forms/1234567/subscriptions`).
3. In `site/index.html`, replace `TODO_OWNER_FORM_ID` in the `<form action=...>` with that ID. The input is already named `email_address`, which Kit expects.
4. Submit a test address and confirm it appears in Kit. Set Kit's confirmation page or double opt-in as you prefer.

## 2. Domain and hosting

No domain is bought yet and Pages settings are unchanged.

1. Buy the domain from any registrar once the name is chosen.
2. Recommended: put the contents of `site/` in a separate tiny repo (for example `pickfight-site`) with Pages enabled and the domain set as its custom domain, plus a `CNAME` file. This keeps the game repo's Pages untouched and avoids a custom domain taking over the project URL.
3. Alternative: move `site/` to `docs/` here and point Pages at `/docs`. Only do this when the domain exists, since it changes the current Pages source.
4. Add the domain to `docs/launch/press-kit.md` (Website field) when live.

## 3. TODO(owner) list

- `TODO_OWNER_FORM_ID`: the Kit form ID (see section 1).
- Steam store page URL: replace the `#` link on the "Wishlist on Steam" button once the page is live (#540).
- Domain: buy it and wire it up (section 2); add press contact and social links to the footer.
