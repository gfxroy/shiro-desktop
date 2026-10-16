# Local models for Shiro

Research checked October 15, 2026. These are recommendations from published model cards and runtime availability, not a controlled benchmark of every model in Shiro. There is no defensible universal “world's best” model, and no model runs well on every PC. Shiro itself currently requires macOS 14 or later; Ollama supports other operating systems.

## Recommended small model

**Qwen3.5-4B** is the recommended starting point in the roughly 4B class for a 16 GB Mac running Shiro's 3 GB VM. It combines coding, native tool use and vision under Apache 2.0. The [publisher's model card](https://huggingface.co/Qwen/Qwen3.5-4B) reports LiveCodeBench v6 55.8, BFCL-V4 50.3 and OSWorld-Verified 35.6. These measure different capabilities and do not establish that a small model will reliably complete long coding tasks. Published thinking-mode scores also do not predict performance with thinking disabled for speed.

Parameter names need care: the [weight metadata](https://huggingface.co/api/models/Qwen/Qwen3.5-4B) reports 4,659,865,088 total parameters, including vision. For a **strict total below 4 billion**, choose [Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B). Phi-4-mini is a 3.8B text-only alternative with documented function calling; it is not presented as the overall winner.

Gemma E4B is not a literal 4B-total model either. Google's [model card](https://ai.google.dev/gemma/docs/core/model_card_4) specifies 4.5B effective parameters and 8B including embeddings. Its mobile-oriented LiteRT bundle can still be compact and useful; the on-disk format, quantization and backend matter alongside parameter count.

## Choices available in the app

| Download identifier | Intended use | Approximate download | Suggested system RAM with Shiro's VM |
| --- | --- | --- | --- |
| `qwen3.5:0.8b` | Very light tasks; limited agent reliability | 1.2–1.3 GB | 8 GB |
| `qwen3.5:2b` | Under-4B choice for lighter machines | 2.7–3.1 GB | 8–12 GB |
| `qwen3.5:4b` | Recommended small coding/tool/vision balance | 3.3–4.0 GB | 16 GB |
| `phi4-mini` | 3.8B text-only coding/tool alternative | 2.5 GB | 12 GB |
| `qwen3.5:9b` | Stronger tools and coding | 6.6–7.6 GB | 24 GB |
| `qwen3.8:27b` | Larger model for demanding coding and agent tasks | 18 GB | 32–48 GB |
| `qwen3.6:35b` | MoE alternative: about 3B active, 35B total | 23–24 GB | 48 GB |
| `qwen3-coder-next` | Dedicated coding agent: 3B active, 80B total | 52 GB | 64+ GB |

Downloads are listed by Ollama for [Qwen3.5](https://ollama.com/library/qwen3.5), [Phi-4-mini](https://ollama.com/library/phi4-mini), [Qwen3.8](https://ollama.com/library/qwen3.8), [Qwen3.6](https://ollama.com/library/qwen3.6) and [Coder Next](https://ollama.com/library/qwen3-coder-next). They may vary with quantization and runtime. RAM figures are engineering estimates for short contexts, the operating system and VM, not vendor guarantees. GPU memory requirements differ on PCs with discrete GPUs. Large context windows increase memory; active MoE parameters describe compute, not how many weights must be stored.

[Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B) is a strong larger upgrade based on its publisher's coding and computer-use results. [Coder Next](https://huggingface.co/Qwen/Qwen3-Coder-Next) is another coding specialist, but its 80B total size excludes it from the small-model category. These are distinct releases, not merely quantizations of Qwen3.5-4B.

Use **Models & connections → Find your next model**, select a card, then **Download & use**. Selecting another model does not delete existing model files. Qwen through Ollama defaults to direct answers in Shiro; **Extra thinking for Qwen** enables slower reasoning. This uses Ollama's documented [reasoning control](https://docs.ollama.com/api/openai-compatibility). Current Ollama and model templates are needed for reliable tool parsing.

## Loading and recovery

The existing LiteRT process was found holding port 9379 while failing to answer `/v1/models`. The old loader then attempted a second server, which failed with “Address already in use.” The updated loader checks health with a short timeout and recovers a stalled process only when its command identifies Shiro's managed runtime and expected loopback bind arguments. It refuses to stop an unrelated application's server. **Restart runtime** is also available on managed model cards.

Activation verifies a short inference before reporting Ready. Local completions use streaming progress, reject incomplete tool-call streams, and have bounded request waits. LiteRT's former `cache:no` default is migrated to `cache:disk`, preserving other settings. Its compiled cache reduces repeated compilation across engine starts; it is not a conversation/prompt cache and does not eliminate token generation time. The first load can still take longer than later requests.

## Match the runtime context to Shiro

Native Memory defaults to an estimated 8,192-token budget, including tools and output. The runtime must also support at least that context. Changing Shiro's budget does not resize the model server's context. Ollama's defaults can differ; a dedicated model alias makes this explicit:

```sh
ollama pull qwen3.5:4b
```

Save a file named `Shiro.Modelfile` containing:

```text
FROM qwen3.5:4b
PARAMETER num_ctx 8192
PARAMETER temperature 0.2
```

Then run `ollama create qwen3.5-shiro:4b -f Shiro.Modelfile` and choose `qwen3.5-shiro:4b` in Shiro. This reuses the downloaded weights. Keep **Extra thinking for Qwen** off for direct responses. Smaller weights can use the same approach with a different `FROM` model. Higher context uses more memory; do not set a budget beyond the runtime's supported limit. See Ollama's [context documentation](https://docs.ollama.com/context-length) and [Modelfile parameters](https://docs.ollama.com/modelfile).
