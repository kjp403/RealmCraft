// Ark Coin storefront.
//
// NO ACCOUNTS, NO SESSIONS. The page collects one thing — the Arkenelle account
// name — and hands it to Stripe as `client_reference_id` on a Payment Link.
// Stripe collects the money and calls our webhook, and the webhook reads that id
// back to decide who to credit. That is the whole linking mechanism, and it is
// why this site can stay a static build with no login.
//
// THE NAME IS CHECKED AGAINST THE LIVE SERVER BEFORE A BUY LINK EXISTS.
// /v1/account/check answers whether that account can be logged into, and the
// buttons stay dead until it says yes. This is not politeness: the webhook will
// not create a wallet for an account that does not exist, so a name that fails
// this check is a payment that reaches nobody and has to be refunded or granted
// by hand. Typing it twice — what this page used to ask for — cannot catch the
// mistake that actually happens, which is a player carefully typing their
// CHARACTER name twice.
//
// A CHECK THAT CANNOT BE MADE BLOCKS THE SALE. If the API is unreachable the
// buttons stay dead and the page says so. Letting them through on a network
// error would restore exactly the failure this file exists to prevent, and a
// player who cannot buy for a minute is a much cheaper mistake than a payment
// nobody can credit.
(function () {
  "use strict";

  var form = document.querySelector("[data-store-form]");
  if (!form) return;

  var nameInput = form.querySelector("[data-store-name]");
  var status = document.querySelector("[data-store-status]");
  var cards = Array.prototype.slice.call(document.querySelectorAll("[data-pkg]"));

  // Mirrors the server's own rule (CredentialsUtils.validate_username): lower
  // cased, 3–20 characters, letters, digits, underscore and single inner spaces.
  // Client-side only, to skip a round trip on something that cannot be a name —
  // the server is the authority on whether it EXISTS.
  var VALID = /^[a-z0-9_]+( [a-z0-9_]+)*$/;
  var MIN_LEN = 3;
  var MAX_LEN = 20;
  var DEBOUNCE_MS = 450;

  // Every answer the server has given us this session, so re-typing a name we
  // already checked is instant and costs the rate limiter nothing.
  var known = Object.create(null);
  var timer = 0;
  var inFlight = null;
  var verified = "";

  function apiUrl() {
    var host = location.hostname;
    if (host === "localhost" || host === "127.0.0.1") return "http://127.0.0.1:8088/v1/account/check";
    return "https://api.arkenelle.com/v1/account/check";
  }

  function normalise(value) {
    return (value || "").trim().toLowerCase().replace(/\s+/g, " ");
  }

  function say(message, kind) {
    if (!status) return;
    status.textContent = message || "";
    status.className = "store-status" + (kind ? " " + kind : "");
  }

  // The buy links only ever carry a name the server has confirmed. Rebuilt from
  // `verified` alone, never from the input, so a name edited after a successful
  // check cannot leave a live link pointing at the old one.
  function paintCards() {
    cards.forEach(function (card) {
      var link = card.querySelector("[data-buy]");
      if (!link) return;
      var base = link.getAttribute("data-href") || "";
      if (base && verified) {
        var join = base.indexOf("?") === -1 ? "?" : "&";
        link.setAttribute("href", base + join + "client_reference_id=" + encodeURIComponent(verified));
        link.removeAttribute("aria-disabled");
      } else {
        // No Payment Link configured for this package at build time, or no
        // confirmed account yet. Either way there is nothing safe to click.
        link.removeAttribute("href");
        link.setAttribute("aria-disabled", "true");
      }
    });
  }

  function setVerified(name) {
    if (verified === name) return;
    verified = name;
    paintCards();
  }

  function shapeError(name) {
    if (!name) return "Enter your Arkenelle account name to continue.";
    if (name.length < MIN_LEN) return "Account names are at least " + MIN_LEN + " characters.";
    if (name.length > MAX_LEN) return "Account names are at most " + MAX_LEN + " characters.";
    if (!VALID.test(name)) return "Letters, digits, underscores and single spaces only.";
    return "";
  }

  function check(name) {
    if (inFlight) inFlight.abort();
    var controller = new AbortController();
    inFlight = controller;
    say("Checking " + name + "…", "");

    fetch(apiUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: name }),
      signal: controller.signal,
    })
      .then(function (response) {
        if (!response.ok) throw new Error("http " + response.status);
        return response.json();
      })
      .then(function (body) {
        var data = (body && body.data) || {};
        if (!body || body.ok !== true || typeof data.exists !== "boolean") {
          throw new Error("bad body");
        }
        known[name] = data.exists;
        // Only speak for the name still in the box — a slow answer for an
        // abandoned name must not overwrite a newer verdict.
        if (normalise(nameInput.value) === name) render(data.exists, name);
      })
      .catch(function (error) {
        if (error && error.name === "AbortError") return;
        if (normalise(nameInput.value) !== name) return;
        setVerified("");
        say("Could not reach the server to check that name. Try again in a moment.", "bad");
      })
      .finally(function () {
        if (inFlight === controller) inFlight = null;
      });
  }

  function render(exists, name) {
    if (exists) {
      setVerified(name);
      say("Account found — coins will be added to " + name + " within a minute of payment.", "good");
      return;
    }
    setVerified("");
    say(
      "No account called " + name + ". This is the name you LOG IN with, " +
        "not your character's name — they are often different.",
      "bad"
    );
  }

  function update() {
    window.clearTimeout(timer);
    var name = normalise(nameInput.value);

    var problem = shapeError(name);
    if (problem) {
      setVerified("");
      say(problem, name ? "bad" : "");
      return;
    }
    if (name in known) {
      render(known[name], name);
      return;
    }
    setVerified("");
    say("Checking that account exists…", "");
    timer = window.setTimeout(function () {
      check(name);
    }, DEBOUNCE_MS);
  }

  // Keep the typed name across a reload — but never the verdict. The check is
  // cheap and the account could have been renamed or removed since.
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

  // No submit button and nothing to post — but Enter in a single-field form
  // still submits it, which would reload the page and lose the check.
  form.addEventListener("submit", function (e) {
    e.preventDefault();
  });

  paintCards();
  update();
})();
