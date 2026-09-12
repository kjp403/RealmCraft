// Ark Coin storefront.
//
// NO ACCOUNTS, NO SESSIONS, NO SERVER. The page collects one thing — the
// Arkenelle account name — and hands it to Stripe as `client_reference_id` on a
// Payment Link. Stripe collects the money and calls our webhook, and the webhook
// reads that id back to decide who to credit. That is the whole linking
// mechanism, and it is why this site can stay a static build with no login.
//
// The trade: a mistyped name is a payment that cannot be credited. The webhook
// refuses to create a wallet for an account that does not exist, so those land
// in the server log for a human rather than silently paying a stranger. The
// confirm step below exists to make that mistake harder.
(function () {
  "use strict";

  var form = document.querySelector("[data-store-form]");
  if (!form) return;

  var nameInput = form.querySelector("[data-store-name]");
  var confirmInput = form.querySelector("[data-store-confirm]");
  var status = document.querySelector("[data-store-status]");
  var cards = Array.prototype.slice.call(document.querySelectorAll("[data-pkg]"));

  // Mirrors the server's own rule (CredentialsUtils): lower-cased, and the set
  // of characters an account name can actually contain. Client-side only to
  // catch typos early — the webhook re-checks the name exists before crediting.
  var VALID = /^[a-z0-9_]{3,20}$/;

  function normalise(value) {
    return (value || "").trim().toLowerCase();
  }

  function say(message, kind) {
    if (!status) return;
    status.textContent = message || "";
    status.className = "store-status" + (kind ? " " + kind : "");
  }

  function update() {
    var name = normalise(nameInput.value);
    var confirmed = normalise(confirmInput.value);
    var ok = false;

    if (!name) {
      say("Enter your Arkenelle account name to continue.", "");
    } else if (!VALID.test(name)) {
      say("That does not look like an account name — letters, numbers and underscores, 3 to 20 characters.", "bad");
    } else if (!confirmed) {
      say("Type it a second time to confirm. Coins go to whatever name you enter here.", "");
    } else if (name !== confirmed) {
      say("The two names do not match.", "bad");
    } else {
      ok = true;
      say("Coins will be added to " + name + " within a minute of payment.", "good");
    }

    cards.forEach(function (card) {
      var link = card.querySelector("[data-buy]");
      if (!link) return;
      var base = link.getAttribute("data-href") || "";
      if (!base) {
        // No Payment Link configured for this package at build time.
        link.removeAttribute("href");
        link.setAttribute("aria-disabled", "true");
        return;
      }
      if (ok) {
        var join = base.indexOf("?") === -1 ? "?" : "&";
        link.setAttribute("href", base + join + "client_reference_id=" + encodeURIComponent(name));
        link.removeAttribute("aria-disabled");
      } else {
        link.removeAttribute("href");
        link.setAttribute("aria-disabled", "true");
      }
    });
  }

  // Keep the typed name across a reload, but never the confirmation — the point
  // of the second field is that it is typed deliberately, every time.
  try {
    var saved = window.localStorage.getItem("arkenelle_store_name");
    if (saved) nameInput.value = saved;
  } catch (e) {}

  nameInput.addEventListener("input", function () {
    try {
      window.localStorage.setItem("arkenelle_store_name", normalise(nameInput.value));
    } catch (e) {}
    update();
  });
  confirmInput.addEventListener("input", update);
  form.addEventListener("submit", function (e) {
    e.preventDefault();
  });

  update();
})();
