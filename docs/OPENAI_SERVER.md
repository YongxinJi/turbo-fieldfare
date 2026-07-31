# Local OpenAI-compatible server

`TurboFieldfareServer` exposes a local Chat Completions API for one Gemma
model. It binds to `127.0.0.1` without authentication or TLS. Do not expose it
through a proxy or tunnel.

## Start with the Mac app

The Mac app installs the model and then starts the bundled server automatically.
It shows the endpoint, model-loading state, readiness, and launch errors. Closing
the app stops only the server process that app instance launched. The bundled
server also exits if its owning app process ends unexpectedly.

The server screen exposes context length, expert-cache slots, temperature,
Top-K, Top-P, chunked prefill, and RDADVISE. The app persists these values next
to the installed model. Use **Apply & Restart** after changing them. Context,
cache, prefill, and RDADVISE are applied when the model reloads. Temperature,
Top-K, and Top-P are request defaults: explicit request fields override the app
values.

The app also generates a Bearer API key and keeps its settings file readable
only by the current user. Copy the key from the configuration card or the
menu-bar menu. The menu-bar label shows the Server RSS and the latest completed
request's decode rate; its menu can reopen the window, copy connection values,
and start or stop the server.

Build and run it from a checkout:

```bash
swift build -c release
.build/release/TurboFieldfareMac
```

For a drag-to-Applications build, run `Scripts/package_dmg.sh` and open
`dist/TurboFieldfare.dmg`.

## Start the server manually

First, install the model with the Mac app or `TurboFieldfareRepack`. Then check
that no other TurboFieldfare model process is running:

```bash
pgrep -fl 'TurboFieldfareServer|TurboFieldfareMac|TurboFieldfareDecodeService|TurboFieldfareCLI|TurboFieldfarePackageTests|swiftpm-testing-helper|mlx_lm|mlx-lm'
```

If the command prints a match, do not start the server.

```bash
swift build -c release --product TurboFieldfareServer
.build/release/TurboFieldfareServer \
  --model scratch/gemma4.gturbo \
  --port 8080 \
  --max-context 16384
```

For an authenticated headless launch, set the key in the process environment:

```bash
TURBOFIELDFARE_API_KEY='replace-with-a-long-random-key' \
  .build/release/TurboFieldfareServer \
  --model scratch/gemma4.gturbo
```

The server loads the model before opening the port. Wait for
`TurboFieldfareServer ready`, then keep the process running while clients use
it.

Check the server from another terminal:

```bash
curl --silent --show-error http://127.0.0.1:8080/health
curl --silent --show-error http://127.0.0.1:8080/v1/models \
  -H "Authorization: Bearer $TURBOFIELDFARE_API_KEY"
curl --silent --show-error http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer $TURBOFIELDFARE_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemma-4-26b-a4b-it",
    "messages": [{"role": "user", "content": "Reply with exactly READY."}],
    "temperature": 0,
    "max_completion_tokens": 16
  }'
```

By default, the server runs one generation and queues up to four requests. Use
`--queue-limit` to change the queue size. Server launch options also include
`--default-temperature`, `--default-top-k`, `--default-top-p`,
`--expert-cache-slots`, `--prefill`, `--prefill-chunk-tokens`, and
`--rdadvise`. Run `TurboFieldfareServer --help` for the accepted values. Press
Control-C to stop the server.

## Connect a client

The base URL is `http://127.0.0.1:8080/v1`. A server launched by the Mac app
requires the generated API key. A headless server requires a key when
`TURBOFIELDFARE_API_KEY` is non-empty.

Python:

```python
import os

from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8080/v1",
    api_key=os.environ["TURBOFIELDFARE_API_KEY"],
)
response = client.chat.completions.create(
    model="gemma-4-26b-a4b-it",
    messages=[{"role": "user", "content": "Say hello in one sentence."}],
)
print(response.choices[0].message.content)
```

OpenCode:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "turbofieldfare": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "TurboFieldfare",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "copy-the-app-api-key-here"
      },
      "models": {
        "gemma-4-26b-a4b-it": {
          "name": "Gemma 4 26B-A4B IT"
        }
      }
    }
  }
}
```

Select `turbofieldfare/gemma-4-26b-a4b-it` in OpenCode.

## Prompt reuse

Single-prefix KV reuse is on by default. Send the complete message history with
every request. When a request continues the retained conversation exactly, the
server reuses the verified KV prefix and reports the number of reused tokens in:

```text
usage.prompt_tokens_details.cached_tokens
```

The server retains one prefix. A different or incompatible history replaces
it. Use `--prompt-cache-mode off` to disable reuse.

## Tool calls

The server can return OpenAI-style function calls, but it cannot authorize or
execute them. The client runs the tool loop:

1. Send function schemas in `tools`.
2. When `finish_reason` is `"tool_calls"`, inspect each function name and JSON
   argument object. Apply the client's normal permission checks before running
   the function.
3. Append the assistant message, including its unchanged `tool_calls`.
4. Append each result as a `role: "tool"` message. Its `tool_call_id` must
   match the call it resolves.
5. Send the complete history and tool schemas again.

The server accepts only function tools. Omit `tool_choice` or set it to `auto`
to allow calls. Set it to `none` to disable them. The server does not support
`required`, named tool selection, or `parallel_tool_calls: false`.

## Supported API

Endpoints:

- `GET /health` (unauthenticated; includes `rss_bytes` and
  `tokens_per_second`)
- `GET /v1/models`
- `POST /v1/chat/completions`

Chat Completions supports JSON and Server-Sent Events responses. Set
`"stream": true` for streaming. Set
`"stream_options": {"include_usage": true}` to receive a final usage chunk.

Requests may contain system, developer, user, assistant, and tool messages.
Supported options include `temperature`, `top_p`, `top_k`,
`repetition_penalty`, `seed`, `stop`, `max_tokens`,
`max_completion_tokens`, and function-tool fields.

When a request omits `temperature`, `top_k`, or `top_p`, the server uses its
launch defaults. Explicit request values always take precedence.

`tokens_per_second` is null until a request completes, then reports that
request's generated-token count divided by its decode time. `rss_bytes` is the
Server process's current resident set size.

The server supports one model and one choice. It does not support the Responses
API, legacy Completions, embeddings, multimodal input, structured output,
batching, log probabilities, or remote model switching.

Context length can be 4K, 8K, 16K, 32K, or 64K. The default is 16K. Larger FP16
KV contexts use more memory. On an 8 GB Mac, run one model process at a time and
watch memory pressure.
