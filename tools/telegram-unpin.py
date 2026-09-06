#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Restore the manual pin in the Telegram discussion group.

Telegram auto-pins every channel post forwarded to the linked discussion
group, displacing the manual pin. This script:
  - learns the manual pin (writes its id to /tmp/newpin for the caller
    to persist into .ci/group-pin.txt),
  - on a channel pin: unpins it and re-pins the recorded manual one,
  - never unpins a manual pin; an empty group means deliberate clear.

Env: TG_TOKEN, TG_GROUP, TG_CHAN, RECORDED (may be empty), OFFSET (may be empty).
Exit 0: nothing to do / done. Exit 1: config or API failure (loud).

Two layers: update EVENTS show who pinned (human actor -> learn, even for
channel content); getChat STATE decides unpin/restore. The event offset is
acked via /tmp/newoffset for the caller to persist.
"""
import json
import os
import sys
import urllib.request
import urllib.parse


def api(token, method, **params):
    base = os.environ.get("TG_API_BASE", "https://api.telegram.org")
    url = "%s/bot%s/%s" % (base, token, method)
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except Exception as e:  # network or HTTP error -> loud, fail open upstream
        return {"ok": False, "description": str(e)}


SERVICE_IDS = {777000, 1087968824}  # Telegram service, anonymous-admin bot


def human(actor):
    return bool(actor) and not actor.get("is_bot") \
        and actor.get("id") not in SERVICE_IDS


def process_events(token, offset):
    """Learn manual pins from pin events. Returns (learned_id, new_offset)."""
    params = {"limit": 100, "timeout": 0}
    if offset:
        params["offset"] = offset
    upds = api(token, "getUpdates", **params)
    if not upds.get("ok"):
        print("getUpdates failed: %s (continuing with state)"
              % upds.get("description", "?"))
        return None, None
    learned, newmax = None, 0
    for u in upds.get("result", []):
        newmax = max(newmax, u.get("update_id", 0))
        msg = u.get("message") or {}
        pm = msg.get("pinned_message")
        if pm and human(msg.get("from")):
            learned = str(pm["message_id"])
    newoff = str(newmax + 1) if newmax else None
    return learned, newoff


def from_channel(pinned, channel):
    return ((pinned.get("sender_chat") or {}).get("id") == channel or
            (pinned.get("forward_from_chat") or {}).get("id") == channel)


def main():
    token = os.environ["TG_TOKEN"]
    group = os.environ["TG_GROUP"]
    channel = int(os.environ["TG_CHAN"])
    recorded = os.environ.get("RECORDED", "")
    learned, newoff = process_events(token, int(os.environ.get("OFFSET") or 0))
    if newoff:
        open("/tmp/newoffset", "w").write(newoff)
    if learned:
        recorded = learned
        if learned != os.environ.get("RECORDED", ""):
            open("/tmp/newpin", "w").write(learned)

    chat = api(token, "getChat", chat_id=group)
    if not chat.get("ok"):
        print("getChat failed: %s" % chat.get("description", "?"))
        return 1
    pinned = chat["result"].get("pinned_message")
    if not pinned:
        print("ACTION=none (group unpinned; respecting clear)")
        return 0
    mid = str(pinned["message_id"])
    if from_channel(pinned, channel):
        if recorded and recorded == mid:
            print("ACTION=keep (recorded pin %s already up)" % mid)
            return 0
        r = api(token, "unpinChatMessage", chat_id=group,
                message_id=pinned["message_id"])
        if (not r.get("ok") and "not pinned" not in r.get("description", "")
                and "not found" not in r.get("description", "")):
            print("unpin FAILED: %s" % r.get("description", "?"))
            return 1
        if recorded and recorded != mid:
            p = api(token, "pinChatMessage", chat_id=group,
                    message_id=int(recorded), disable_notification=True)
            if p.get("ok"):
                print("ACTION=restored (unpinned %s, re-pinned %s)"
                      % (mid, recorded))
            elif "not found" in p.get("description", ""):
                print("ACTION=cleared (recorded pin %s gone)" % recorded)
                open("/tmp/newpin", "w").write("")
            else:
                print("re-pin FAILED: %s" % p.get("description", "?"))
                return 1
        else:
            print("ACTION=unpinned (no manual pin recorded)")
        return 0
    if mid != recorded:
        open("/tmp/newpin", "w").write(mid)
        print("ACTION=learned (manual pin %s)" % mid)
    else:
        print("ACTION=keep (manual pin %s already recorded)" % mid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
