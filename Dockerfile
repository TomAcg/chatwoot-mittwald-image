FROM chatwoot/chatwoot:latest

LABEL org.opencontainers.image.source="https://github.com/tomacg/chatwoot-mittwald-image"
LABEL org.opencontainers.image.description="Chatwoot image patched so Captain AI can use Mittwald AI Hosting (gpt-oss-120b) instead of only OpenAI/Anthropic/Gemini cloud models."
LABEL org.opencontainers.image.licenses="MIT"

COPY llm.yml /app/config/llm.yml
COPY llm_models.json /app/config/llm_models.json
