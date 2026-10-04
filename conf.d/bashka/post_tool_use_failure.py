"""Steer a failed commit/tag signing to the user, never a bypass.

Claude reports a failed Bash call as PostToolUseFailure with an `error` string. Grok fires
PostToolUseFailure only for dispatch failures; a non-zero run_terminal_command exit arrives as
PostToolUse with the tagged result in `toolResult` (aliased as `tool_response`).
"""

import json
import re
import sys

SHELL_TOOLS = {"Bash", "run_terminal_command"}
RESULT_TEXT = ("output_for_prompt", "output", "stdout", "stderr")
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
    "`launchctl kickstart -k gui/$(id -u)/org.nix-community.home.ssh-signing-agent` "
    "(macOS) or `systemctl --user restart ssh-signing-agent` (Linux), then retry the same "
    "command once they confirm."
)


def failure_text(payload, event):
    if event == "PostToolUseFailure":
        error = payload.get("error")
        return error if isinstance(error, str) else None
    if event == "PostToolUse":
        result = payload.get("toolResult", payload.get("tool_response"))
        if isinstance(result, dict) and result.get("exit_code") not in (0, None):
            return "\n".join(str(result.get(key, "")) for key in RESULT_TEXT)
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        event = payload.get("hook_event_name")
        tool = payload.get("tool_name", payload.get("toolName"))
        if tool not in SHELL_TOOLS:
            return
        text = failure_text(payload, event)
        if text and SIGNING_FAILURE.search(text):
            print(
                json.dumps(
                    {
                        "hookSpecificOutput": {
                            "hookEventName": event,
                            "additionalContext": MESSAGE,
                        }
                    }
                )
            )
    except (ValueError, AttributeError, TypeError, OSError):
        return


if __name__ == "__main__":
    main()
