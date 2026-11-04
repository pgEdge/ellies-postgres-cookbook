"""
Ellie's Postgres Cookbook
Chatting with the LLM through the AI DBA Workbench API, using httpx.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import os
import sys

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
def settings() -> dict:
    """Reads the settings from the environment.

    The or operator treats an empty variable as unset.
    """
    token = os.environ.get("WORKBENCH_TOKEN") or ""
    if not token:
        raise RuntimeError("WORKBENCH_TOKEN must be set")
    return {
        "base_url": (
            os.environ.get("WORKBENCH_URL") or "http://localhost:8080"
        ).rstrip("/"),
        "token": token,
    }
# --8<-- [end:config]


# --8<-- [start:request]
def api(cfg: dict, method: str, path: str, **kwargs) -> httpx.Response:
    """Sends a request to the API and returns the response.

    A request that the server rejects raises an error that includes the
    message from the server, which raise_for_status alone would leave out.
    """
    # A small model on a CPU can take a while to answer, so the timeout is
    # generous.
    response = httpx.request(
        method, f"{cfg['base_url']}/api/v1{path}", timeout=300,
        headers={"Authorization": f"Bearer {cfg['token']}"}, **kwargs,
    )
    if response.is_error:
        raise RuntimeError(
            f"{method} {path} failed with status {response.status_code}: "
            f"{response.text.strip()}"
        )
    return response
# --8<-- [end:request]


# --8<-- [start:providers]
def show_provider(cfg: dict) -> None:
    """Prints the default provider and model, which the chat endpoint uses
    when a request names neither."""
    reply = api(cfg, "GET", "/llm/providers").json()
    default = next((p for p in reply["providers"] if p["isDefault"]), None)
    if default is None:
        raise RuntimeError("The Workbench has no default LLM provider")
    print(f"Provider: {default['name']} (model {reply['defaultModel']})")
# --8<-- [end:providers]


# --8<-- [start:chat]
def chat(cfg: dict, messages: list) -> dict:
    """Sends a conversation to the model and returns the reply.

    The messages are the conversation so far, each with a role of user or
    assistant and some content.
    """
    return api(cfg, "POST", "/llm/chat", json={"messages": messages}).json()


def reply_text(reply: dict) -> str:
    """Returns the text of a reply on a single line.

    A small model may spread its answer over several lines, so the function
    joins the text blocks and collapses the white space. It fails when the
    reply holds no text.
    """
    blocks = [b["text"] for b in reply["content"] if b["type"] == "text"]
    text = " ".join(" ".join(blocks).split())
    if not text:
        raise RuntimeError("The model returned no text")
    return text
# --8<-- [end:chat]


# --8<-- [start:main]
def main() -> int:
    try:
        cfg = settings()
        show_provider(cfg)

        # The first message starts the conversation.
        question = "Name one type of PostgreSQL index, in one sentence."
        messages = [{"role": "user", "content": question}]
        text = reply_text(chat(cfg, messages))
        print(f"Reply: {text}")

        # The server keeps no conversation, so the follow-up repeats the
        # earlier messages, including the model's reply, and adds the new
        # question.
        messages += [
            {"role": "assistant", "content": text},
            {"role": "user",
             "content": "Summarise your answer in five words."},
        ]
        follow_up = chat(cfg, messages)
        print(f"Follow-up reply: {reply_text(follow_up)}")
        print(f"Stop reason: {follow_up['stop_reason']}")
    # httpx.HTTPError covers failures to connect, and RuntimeError covers
    # replies that the server rejected or that lacked what we need.
    except (httpx.HTTPError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
