# chatwoot-mittwald-image

A patched build of [`chatwoot/chatwoot`](https://hub.docker.com/r/chatwoot/chatwoot) that lets **Captain AI** (Chatwoot's built-in AI agent) use **Mittwald AI Hosting's `gpt-oss-120b`** model instead of being limited to OpenAI/Anthropic/Gemini cloud models.

Published as: `ghcr.io/tomacg/chatwoot-mittwald:latest`, plus one tag per upstream release (e.g. `:v4.19.1`, `:v4.17.1`) to roll back to.

Currently based on Chatwoot **v4.19.1** (pinned in the `Dockerfile`).

## Why this exists

Chatwoot self-hosted lets you configure a custom OpenAI-compatible provider for Captain under **Super Admin → Settings → Captain** (`CAPTAIN_OPEN_AI_API_KEY`, `CAPTAIN_OPEN_AI_MODEL`, `CAPTAIN_OPEN_AI_ENDPOINT`). In practice (Chatwoot v4.17.1) this only half-works out of the box:

1. **Only one Captain feature respects the custom model setting.** Internally, Chatwoot routes every AI feature (reply suggestions, rewrite/summarize, FAQ generation, the agent copilot, the automatic reply bot, etc.) through `config/llm.yml`, a per-feature whitelist of models aimed at Chatwoot Cloud's credit-billing system (GPT-4.1/5.x, Claude, Gemini only). Only the `conversation_completion` feature (the actual auto-reply bot) has an explicit code path that honors `CAPTAIN_OPEN_AI_MODEL` for self-hosted installs. Every other feature (`editor` — i.e. "Suggest a reply", `assistant`, `copilot`, `label_suggestion`, FAQ generation, etc.) ignores your custom model entirely and always requests a hardcoded cloud model name, which a self-hosted-only endpoint like Mittwald's obviously doesn't serve.
2. **The custom endpoint gets a doubled `/v1` if you follow Mittwald's own docs literally.** `lib/captain/base_task_service.rb` always appends `/v1` to whatever you put in `CAPTAIN_OPEN_AI_ENDPOINT`. Mittwald's docs recommend `https://llm.aihosting.mittwald.de/v1` as the base URL, which becomes `.../v1/v1/chat/completions` — a 404 from Mittwald's own nginx. **Fix: set the endpoint to `https://llm.aihosting.mittwald.de` (no trailing `/v1`).** This isn't something this image patches — it's just an install-config gotcha, documented here for the next person.
3. **RubyLLM (the underlying LLM client library) misidentifies `gpt-oss-120b` as an Azure-hosted model.** Chatwoot ships a large static model registry at `config/llm_models.json` (used by the `ruby_llm` gem to auto-detect which provider/client to use for a given model name, since the app doesn't pass an explicit `provider:` when calling the model). That registry has an exact-match entry `{"id": "gpt-oss-120b", "provider": "azure", ...}` — because `gpt-oss-120b` is commonly served via Azure AI Foundry. Since Chatwoot never tells RubyLLM which provider to use explicitly, it picks Azure and then fails with `Missing configuration for Azure: azure_api_base, azure_api_key or azure_ai_auth_token`, even though we only configured an OpenAI-compatible endpoint.

This image fixes (1) and (3) by overlaying two files from the stock image:

- **`config/llm.yml`** — added `gpt-oss-120b` as a model, and set it as the `default` for every *text/chat* Captain feature (as of v4.19.1: `conversation_completion`, `editor`, `assistant`, `copilot`, `copilot_workflows`, `document_faq_generation`, `conversation_faq_generation`, `conversation_faq_matching`, `help_center_article_generation`, `onboarding_content_generation`, `help_center_query_translation`, `message_translation`, `language_detection`). Deliberately **left untouched**: `pdf_faq_generation` (gpt-oss-120b likely has no vision support, needed to read PDF pages), `audio_transcription` and `call_announcement` (audio models, different modality), `help_center_search` (an embedding feature — handled separately via `CAPTAIN_EMBEDDING_MODEL`, see below, not via `llm.yml`).
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
docker buildx build --platform linux/amd64 -t ghcr.io/tomacg/chatwoot-mittwald:<tag> -t ghcr.io/tomacg/chatwoot-mittwald:latest --push .
```

When upstream Chatwoot ships a new version:

1. Keep the running image reachable for a rollback, e.g. `docker buildx imagetools create -t ghcr.io/tomacg/chatwoot-mittwald:<old tag> ghcr.io/tomacg/chatwoot-mittwald:latest` (skip if that tag already exists).
2. Run `python3 patch.py <tag>` (e.g. `v4.19.1`). It downloads `config/llm.yml` and `config/llm_models.json` from that `chatwoot/chatwoot` release and re-applies both patches described above. New text features get `gpt-oss-120b` automatically; check new features against the skip list in `patch.py`.
3. Set the same tag in the `Dockerfile`'s `FROM` line.
4. Rebuild and push with the command above.
5. On the Mittwald side, force a fresh pull — since the tag stays `:latest`, mStudio won't automatically notice new content:
   ```bash
   mw container recreate -p <project-id> <container-id> --pull --force
   ```
   (once for the `rails` container, once for `sidekiq`).

## Email threading by contact

Chatwoot only threads an incoming email into an existing conversation when its `In-Reply-To`/`References` headers point at a message Chatwoot knows. Replies to mails Chatwoot never sent (shop order/shipping confirmations from Shopify/Shopware) therefore always open a new conversation, and customers who reply to every status mail end up with several parallel conversations.

`email_thread_by_contact.rb` (copied to `config/initializers/zz_email_thread_by_contact.rb`) prepends a fallback to `Imap::ImapMailbox#find_conversation_by_reference_ids`, which is used by both IMAP and Microsoft (Graph) email inboxes: if no conversation matches the headers, the mail goes into the contact's most recently active conversation in the same inbox, as long as that activity is newer than N days. Resolved conversations are reopened by Chatwoot's own `Message#reopen_conversation`. Auto-replies (out-of-office etc.) are never threaded this way. Each threaded mail logs `EmailThreadByContact: mail <message-id> -> conversation <display id>`.

It is off unless enabled per inbox via env vars on **both** `rails` and `sidekiq` (the IMAP fetch runs in sidekiq):

| Env | Meaning |
|---|---|
| `EMAIL_THREAD_BY_CONTACT_INBOX_IDS` | comma-separated inbox IDs, e.g. `3` (Kardena `service@kardena.de`). Empty/unset = patch inactive |
| `EMAIL_THREAD_BY_CONTACT_DAYS` | max. age of the last activity in the target conversation, default `14` |

Side effect: the agent's reply goes out with the subject of the older conversation.

When rebasing onto a new upstream release, check that `app/mailboxes/imap/imap_mailbox.rb` still has a private `find_conversation_by_reference_ids` that returns a conversation or `nil`; otherwise the fallback silently stops working (a new conversation is created, nothing breaks).

### Deployment (Kasefilters/Kardena, since 2026-11-03)

`rails` (`c-ksaivx`) and `sidekiq` (`c-n9t3hs`) in project `p-yx1wti` run the pinned tag `ghcr.io/tomacg/chatwoot-mittwald:v4.19.1-mailthread` (not `:latest`) with `EMAIL_THREAD_BY_CONTACT_INBOX_IDS=3` and `EMAIL_THREAD_BY_CONTACT_DAYS=14`. `v4.19.1` is the same build without this initializer.

Caution: `mw container update -e/--env-file` **replaces the whole env** of a container. Change single variables in mStudio (container → environment variables), or build a complete env file from `mw container list -o json` (`deployedState.envs`) first.

### Rollback

Pick the lightest step that's enough:

1. **Switch it off without changing the image:** in mStudio, delete `EMAIL_THREAD_BY_CONTACT_INBOX_IDS` on `sidekiq` (fetches the mails) and `rails`, then recreate both. New mails are threaded by headers only again. Conversations already merged stay merged.
2. **Remove the code:** go back to the image without the patch (env vars stay, they are just ignored):
   ```bash
   mw container update c-n9t3hs -p p-yx1wti --image ghcr.io/tomacg/chatwoot-mittwald:v4.19.1 --recreate   # sidekiq
   mw container update c-ksaivx -p p-yx1wti --image ghcr.io/tomacg/chatwoot-mittwald:v4.19.1 --recreate   # rails
   ```
   In this repo, `git revert` the commit that added `email_thread_by_contact.rb`, so the next rebuild doesn't bring it back.
3. **Split a wrongly merged mail out again:** Chatwoot has no "split conversation". Answer it in the conversation it landed in, or start a new conversation for the contact by hand and copy the text over.

## Where this is deployed

Referenced from the `rails` and `sidekiq` services of a Mittwald mStudio container stack running the rest of a standard Chatwoot Docker deployment (`postgres`/`pgvector`, `redis`). That compose file (with real credentials) is kept private/local, not in this repo.
