# Runtime controls

The Mac app is an installer and launcher for the loopback OpenAI-compatible
server. Its server screen exposes the supported production runtime controls
while keeping FP16 as the fixed KV format.

## Mac app controls

| Control | Values | Default | When it applies |
| --- | --- | --- | --- |
| Context length | 4K, 8K, 16K, 32K, 64K | 4K | Model reload |
| Expert-cache slots | 8, 16, 24, 32 | 16 | Model reload |
| Temperature | 0 to 2 | 0.2 | API request default |
| Top-K | Off, or 1 to 256 | 64 | API request default |
| Top-P | Off, or 0.01 to 1 | 0.95 | API request default |
| Chunked prefill | On or off | On | Model reload |
| RDADVISE | Off, default, bounded, adaptive | Off | Model reload |

The app persists these settings next to the installed model. Changing a value
while the owned server is running shows **Apply & Restart**. Sampling values
become defaults only when an API request omits the corresponding field, so
clients can still override temperature, Top-K, and Top-P per request.

The same settings file contains an app-generated API key and is written with
owner-only permissions. Rotating the key requires a server restart. The
menu-bar label reports Server RSS and the latest completed request's decode
token rate.

## Generation controls

The API and CLI expose these request controls:

| Control | API field | CLI flag | Default | Effect |
| --- | --- | --- | --- | --- |
| Maximum response | `max_completion_tokens` or `max_tokens` | `--max-new` | Remaining server context; CLI: 1,024 tokens | Limits generated tokens. |
| Maximum context | Server launch option | `--max-context` | Server: 16K; CLI: 4K | Sets prompt plus response capacity. |
| Temperature | `temperature` | `--temperature` | 0.2 | `0` is greedy; positive values sample. |
| Top-K | `top_k` | `--top-k` | 64 | Keeps at most K candidates. CLI `0` turns it off. |
| Top-P | `top_p` | `--top-p` | 0.95 | Applies nucleus truncation before Top-K. |
| Repetition penalty | `repetition_penalty` | `--repetition-penalty` | 1.0 | Penalizes recently sampled tokens. |
| Seed | `seed` | `--seed` | Runtime-selected | Makes otherwise equivalent sampled requests reproducible. |

With positive temperature, a CLI Top-P below `1` requires Top-K between `1`
and `256`. To disable both truncation controls in the CLI, pass
`--top-k 0 --top-p 1`.

## Server runtime

| Control | Values | CLI flag | Production default | Effect |
| --- | --- | --- | --- | --- |
| Expert-cache slots | 8, 16, 24, 32 | `--expert-cache-slots` | 16 | More slots can retain more routed experts and reduce later reads, but values above 16 use more RAM. |
| Prompt prefill | On, off | — | On | On processes known prompt tokens through the chunked prefill path. Off disables that path. |
| RDADVISE | Off, Default, Bounded, Adaptive | `--rdadvise` | Off | Applies experimental read advice. Its effect depends on the workload; it may help a short decode and slow a long one. |

The CLI and server apply these settings when they load a model. The Mac app
exposes the same supported load-time controls and restarts only the server it
owns when they change. Setting `TURBO_FIELDFARE_PHASES=1` makes the CLI print
the decode phase split (`cb1`, expert I/O await, `cb2`, and GPU waits) after
the timing footer; it is a diagnostic and does not change behavior.

The Mac app keeps these server properties fixed:

- loopback port `8080`
- queue limit `4`
- single-prefix prompt reuse

The API model ID is derived from the selected installed family:
`gemma-4-26b-a4b-it` or `qwen3.6-35b-a3b`.

Use the standalone `TurboFieldfareServer` executable when a different supported
port, queue limit, model ID, prompt-cache mode, or prefill chunk size is
required. See [Local OpenAI-compatible server](OPENAI_SERVER.md) for its
command-line options and API behavior.

## Results

The API reports prompt, completion, total, and reused prompt-token counts in the
OpenAI-compatible `usage` object. The CLI writes its complete timing footer to
standard error unless `--quiet` is passed. A measured result remains a data
point rather than a performance ceiling; use the
[community benchmark protocol](COMMUNITY_BENCHMARKS.md) for comparable results.
