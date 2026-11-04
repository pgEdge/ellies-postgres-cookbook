"""
Ellie's Postgres Cookbook
Streaming an answer from the pgEdge RAG Server, using httpx.

These examples are for pgEdge RAG Server 2.0.0.

Copyright (c) 2026, pgEdge, Inc.
This code is released under the PostgreSQL License.
"""

# --8<-- [start:imports]
import json
import os
import sys
from collections.abc import Iterable, Iterator
from urllib.parse import quote

import httpx
# --8<-- [end:imports]


# --8<-- [start:config]
# The or operator treats an empty variable as unset.
BASE_URL = (os.environ.get("RAG_SERVER_URL") or "http://localhost:8080").rstrip("/")
PIPELINE = os.environ.get("RAG_PIPELINE") or "cookbook"

QUESTION = "How long does the Acme Widget 2.0 take to charge?"

# The timeout applies to each wait for data rather than to the whole
# stream, but the server may wait for the language model to begin, and a
# small model on a modest machine can take a while, so allow plenty of
# time.
TIMEOUT_SECONDS = 300.0
# --8<-- [end:config]


# --8<-- [start:events]
def read_events(lines: Iterable[str]) -> Iterator[dict]:
    """Parses Server-Sent Events, and yields the JSON object that the data
    of each event holds.

    An event is one or more "data:" lines followed by a blank line. The
    stream may end without the final blank line, so the last event is sent
    when the lines run out as well.
    """
    data: list[str] = []
    for line in lines:
        if line == "":
            if data:
                yield json.loads("\n".join(data))
                data = []
        elif line.startswith("data:"):
            # A single space after the colon is not part of the data.
            data.append(line[len("data:"):].removeprefix(" "))
        # Comment lines (which start with a colon) and other fields are
        # ignored.
    if data:
        yield json.loads("\n".join(data))
# --8<-- [end:events]


# --8<-- [start:stream]
class RagError(Exception):
    """Raised when the RAG Server rejects a request or the stream fails."""


def error_text(response: httpx.Response) -> str:
    """Describes an error response, which carries a JSON body of the form
    {"error": {"code": "...", "message": "..."}}."""
    try:
        error = response.json()["error"]
        return f"{error['code']}: {error['message']}"
    except (ValueError, KeyError, TypeError):
        return response.text[:200] or response.reason_phrase


def stream_answer(client: httpx.Client, question: str) -> int:
    """Prints the answer as it arrives, and returns the number of chunks."""
    chunks = 0
    error = None
    done = False

    with client.stream(
        "POST",
        f"/v1/pipelines/{quote(PIPELINE, safe='')}",
        json={"query": question, "stream": True},
    ) as response:
        # A request the server rejects gets an ordinary error status. Once
        # streaming starts the status is always 200, so later failures
        # arrive as events instead.
        if response.is_error:
            response.read()
            raise RagError(f"HTTP {response.status_code}, {error_text(response)}")

        for event in read_events(response.iter_lines()):
            kind = event.get("type")
            if kind == "chunk":
                # The last chunk has no content, so use get().
                content = event.get("content", "")
                if content:
                    print(content, end="", flush=True)
                    chunks += 1
            elif kind == "error":
                error = event.get("error") or "unknown error"
            elif kind == "done":
                done = True

    print()
    # The server sends a done event after an error event, so keep reading
    # until the stream ends before reporting the error.
    if error:
        raise RagError(f"The stream reported an error: {error}")
    if not done:
        raise RagError("The stream ended before the done event")
    return chunks
# --8<-- [end:stream]


# --8<-- [start:main]
def main() -> int:
    print(f"Question: {QUESTION}")
    print("Answer:")
    try:
        with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT_SECONDS) as client:
            chunks = stream_answer(client, QUESTION)
    # json.JSONDecodeError is a ValueError, raised for an event whose data
    # is not valid JSON.
    except (httpx.HTTPError, RagError, ValueError) as e:
        print(f"RAG Server error: {e}", file=sys.stderr)
        return 1

    print(f"Chunks received: {chunks}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
# --8<-- [end:main]
