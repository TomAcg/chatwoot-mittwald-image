# chatwoot-mittwald-image

A patched build of [`chatwoot/chatwoot`](https://hub.docker.com/r/chatwoot/chatwoot) that lets **Captain AI** (Chatwoot's built-in AI agent) use **Mittwald AI Hosting's `gpt-oss-120b`** model instead of being limited to OpenAI/Anthropic/Gemini cloud models.

Published as: `ghcr.io/tomacg/chatwoot-mittwald:latest`

## Why this exists

Chatwoot self-hosted lets you configure a custom OpenAI-compatible provider for Captain under **Super Admin → Settings → Captain** (`CAPTAIN_OPEN_AI_API_KEY`, `CAPTAIN_OPEN_AI_MODEL`, `CAPTAIN_OPEN_AI_ENDPOINT`). In practice (Chatwoot v4.17.1) this only half-works out of the box:

1. **Only one Captain feature respects the custom model setting.** Internally, Chatwoot routes every AI feature (reply suggestions, rewrite/summarize, FAQ generation, the agent copilot, the automatic reply bot, etc.) through `config/llm.yml`, a per-feature whitelist of models aimed at Chatwoot Cloud's credit-billing system (GPT-4.1/5.x, Claude, Gemini only). Only the `conversation_completion` feature (the actual auto-reply bot) has an explicit code path that honors `CAPTAIN_OPEN_AI_MODEL` for self-hosted installs. Every other feature (`editor` — i.e. "Suggest a reply", `assistant`, `copilot`, `label_suggestion`, FAQ generation, etc.) ignores your custom model entirely and always requests a hardcoded cloud model name, which a self-hosted-only endpoint like Mittwald's obviously doesn't serve.
2. **The custom endpoint gets a doubled `/v1` if you follow Mittwald's own docs literally.** `lib/captain/base_task_service.rb` always appends `/v1` to whatever you put in `CAPTAIN_OPEN_AI_ENDPOINT`. Mittwald's docs recommend `https://llm.aihosting.mittwald.de/v1` as the base URL, which becomes `.../v1/v1/chat/completions` — a 404 from Mittwald's own nginx. **Fix: set the endpoint to `https://llm.aihosting.mittwald.de` (no trailing `/v1`).** This isn't something this image patches — it's just an install-config gotcha, documented here for the next person.
3. **RubyLLM (the underlying LLM client library) misidentifies `gpt-oss-120b` as an Azure-hosted model.** Chatwoot ships a large static model registry at `config/llm_models.json` (used by the `ruby_llm` gem to auto-detect which provider/client to use for a given model name, since the app doesn't pass an explicit `provider:` when calling the model). That registry has an exact-match entry `{"id": "gpt-oss-120b", "provider": "azure", ...}` — because `gpt-oss-120b` is commonly served via Azure AI Foundry. Since Chatwoot never tells RubyLLM which provider to use explicitly, it picks Azure and then fails with `Missing configuration for Azure: azure_api_base, azure_api_key or azure_ai_auth_token`, even though we only configured an OpenAI-compatible endpoint.

This image fixes (1) and (3) by overlaying two files from the stock image:

- **`config/llm.yml`** — added `gpt-oss-120b` as a model, and set it as the `default` for every *text/chat* Captain feature (`conversation_completion`, `editor`, `assistant`, `copilot`, `label_suggestion`, `document_faq_generation`, `conversation_faq_generation`, `conversation_faq_matching`, `help_center_article_generation`, `onboarding_content_generation`, `help_center_query_translation`). Deliberately **left untouched**: `pdf_faq_generation` (gpt-oss-120b likely has no vision support, needed to read PDF pages), `audio_transcription` (Whisper-only, different modality), `help_center_search` (an embedding feature — handled separately via `CAPTAIN_EMBEDDING_MODEL`, see below, not via `llm.yml`).
- **`config/llm_models.json`** — changed the single exact-match entry `id: "gpt-oss-120b"` from `"provider": "azure"` to `"provider": "openai"`, so RubyLLM routes it through the generic OpenAI-compatible client (which respects our configured `openai_api_base`/`openai_api_key`) instead of demanding Azure credentials.

Fix (2) is **not** baked into the image — it's just an installation-config value. Make sure `CAPTAIN_OPEN_AI_ENDPOINT` is set without a trailing `/v1`.

## Required Chatwoot Super Admin settings (Settings → Captain)

| Field | Value |
|---|---|
| OpenAI API Key | your Mittwald AI Hosting API key (created in mStudio) |
| OpenAI Model | `gpt-oss-120b` |
| OpenAI API Endpoint | `https://llm.aihosting.mittwald.de` (**no** trailing `/v1`) |
| Embedding Model | `Qwen3-Embedding-8B` (needed for Captain's document/FAQ knowledge-base features, which use a separate embeddings call — Mittwald doesn't serve OpenAI's default `text-embedding-3-small`) |

## Rebuilding / updating for a new upstream Chatwoot release

Mittwald's hosts run `linux/amd64`; build accordingly even from an Apple Silicon Mac:

```bash
docker buildx build --platform linux/amd64 -t ghcr.io/tomacg/chatwoot-mittwald:latest --push .
```

When upstream Chatwoot ships a new version:

1. Pull the new `config/llm.yml` and `config/llm_models.json` from the matching `chatwoot/chatwoot` release tag on GitHub.
2. Re-apply the same two patches described above (add `gpt-oss-120b` to `llm.yml`'s relevant feature defaults + models lists; flip its `llm_models.json` entry from `azure` to `openai`).
3. Rebuild and push with the command above.
4. On the Mittwald side, force a fresh pull — since the tag stays `:latest`, mStudio won't automatically notice new content:
   ```bash
   mw container recreate -p <project-id> <container-id> --pull --force
   ```
   (once for the `rails` container, once for `sidekiq`).

## Where this is deployed

Referenced from the `rails` and `sidekiq` services of a Mittwald mStudio container stack running the rest of a standard Chatwoot Docker deployment (`postgres`/`pgvector`, `redis`). That compose file (with real credentials) is kept private/local, not in this repo.
