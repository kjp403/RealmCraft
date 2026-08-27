"""Gateway login helper for the Trading Post end-to-end test.

Walks the same public HTTP endpoints the real launcher uses (login -> list
characters -> enter world) and prints the world connection details as
`address port auth-token`, ready to feed into tools/market_bot.tscn.

    python tools/market_enter.py mktseller Testpass123

Local stack only: it targets 127.0.0.1:8088 by default.
"""

import json
import sys
import urllib.request

GATEWAY = "http://127.0.0.1:8088"
VERSION = "0.28.171"


def post(path, payload):
    request = urllib.request.Request(
        GATEWAY + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    return json.load(urllib.request.urlopen(request, timeout=15))


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: market_enter.py <account> <password> [character]")
    account, password = sys.argv[1], sys.argv[2]
    wanted = sys.argv[3] if len(sys.argv) > 3 else None

    login = post("/v1/login", {"a-u": account, "a-p": password, "c-v": VERSION})
    if "error" in login:
        sys.exit("login failed: %s" % login)
    session, account_id = login["session_id"], login["id"]
    world_id = int(next(iter(login["w"])))

    # The response IS the character map: {"<char_id>": {name, level, skin, class}}.
    characters = post(
        "/v1/world/characters",
        {"w-id": world_id, "a-id": account_id, "a-u": account, "t-id": session},
    )
    if "error" in characters or not characters:
        sys.exit("account %s has no character in world %d" % (account, world_id))

    char_id = None
    for key, entry in characters.items():
        if wanted is None or str(entry.get("name", "")).lower() == wanted.lower():
            char_id = int(key)
            break
    if char_id is None:
        sys.exit("no character named %s on %s" % (wanted, account))

    entered = post(
        "/v1/world/enter",
        {"t-id": session, "a-u": account, "w-id": world_id, "c-id": char_id},
    )
    if "error" in entered:
        sys.exit("enter failed: %s" % entered)
    print("%s %s %s" % (entered["address"], entered["port"], entered["auth-token"]))


if __name__ == "__main__":
    main()
