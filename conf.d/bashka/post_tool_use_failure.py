"""PostToolUseFailure: steer a failed commit/tag signing to the user, never a bypass."""

import json
import re
import sys

SIGNING_FAILURE = re.compile(
    r"Error connecting to agent"
    r"|No private key found"
    r"|agent refused operation"
    r"|Couldn't (?:find key in agent|sign message)"
    r"|gpg failed to sign"
)
MESSAGE = (
    "Signing failed: the dedicated ssh-signing-agent is not reachable or holds no key. "
    "Do not retry with signing turned off (--no-gpg-sign, --no-sign, "
    "-c commit.gpgsign=false) or route around it. Stop and tell the user to run "
    "`launchctl kickstart -k gui/$(id -u)/org.nix-community.home.ssh-signing-agent`, "
    "then retry the same command once they confirm."
)


def main():
    try:
        payload = json.load(sys.stdin)
        error = payload.get("error")
        if payload.get("tool_name") != "Bash" or not isinstance(error, str):
            return
        if SIGNING_FAILURE.search(error):
            print(
                json.dumps(
                    {
                        "hookSpecificOutput": {
                            "hookEventName": "PostToolUseFailure",
                            "additionalContext": MESSAGE,
                        }
                    }
                )
            )
    except (ValueError, AttributeError, OSError):
        return


if __name__ == "__main__":
    main()
