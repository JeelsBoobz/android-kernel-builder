#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Restore the manual pin in the Telegram discussion group.

Telegram auto-pins every channel post forwarded to the linked discussion
group, displacing the manual pin. This script:
  - learns the manual pin (writes its id to /tmp/newpin for the caller
    to persist into .ci/group-pin.txt),
  - on a channel pin: unpins it and re-pins the recorded manual one,
  - never unpins a manual pin; an empty group means deliberate clear.

Env: TG_TOKEN, TG_GROUP, TG_CHAN, RECORDED (may be empty).
Exit 0: nothing to do / done. Exit 1: config or API failure (loud).
"""
import json
import os
import sys
import urllib.request
import urllib.parse


def api(token, method, **params):
    url = "https://api.telegram.org/bot%s/%s" % (token, method)
    data = urllib.parse.urlencode(params).encode()
    try:
        with urllib.request.Request(url, data=data) as req:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.load(r)
    except Exception as e:  # network or HTTP error -> loud, fail open upstream
        return {"ok": False, "description": str(e)}


def from_channel(pinned, channel):
    return ((pinned.get("sender_chat") or {}).get("id") == channel or
            (pinned.get("forward_from_chat") or {}).get("id") == channel)


def main():
    token = os.environ["TG_TOKEN"]
    group = os.environ["TG_GROUP"]
    channel = int(os.environ["TG_CHAN"])
    recorded = os.environ.get("RECORDED", "")

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
