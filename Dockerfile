FROM chatwoot/chatwoot:v4.19.1

LABEL org.opencontainers.image.source="https://github.com/tomacg/chatwoot-mittwald-image"
LABEL org.opencontainers.image.description="Chatwoot image patched so Captain AI can use Mittwald AI Hosting (gpt-oss-120b) instead of only OpenAI/Anthropic/Gemini cloud models."
LABEL org.opencontainers.image.licenses="MIT"

COPY llm.yml /app/config/llm.yml
COPY llm_models.json /app/config/llm_models.json
# Thread emails by contact when headers don't match (see README, "Email threading by contact")
COPY email_thread_by_contact.rb /app/config/initializers/zz_email_thread_by_contact.rb
