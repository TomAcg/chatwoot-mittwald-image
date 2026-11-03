# Patch: E-Mails ohne passende In-Reply-To/References-Header (z. B. Antworten auf
# Shop-Versandmails) an das letzte Gespräch desselben Kontakts im selben Postfach
# hängen, statt ein neues Gespräch anzulegen. Erledigte Gespräche öffnet Chatwoot
# dabei selbst wieder (Message#reopen_conversation).
#
# Steuerung per Env (rails + sidekiq):
#   EMAIL_THREAD_BY_CONTACT_INBOX_IDS  kommagetrennte Inbox-IDs, leer = Patch aus
#   EMAIL_THREAD_BY_CONTACT_DAYS       max. Alter der letzten Aktivität (Standard 14)
module EmailThreadByContact
  private

  def find_conversation_by_reference_ids
    super || find_recent_conversation_by_contact
  end

  def find_recent_conversation_by_contact
    inbox_ids = ENV.fetch('EMAIL_THREAD_BY_CONTACT_INBOX_IDS', '').split(',').map { |id| id.strip.to_i }
    return unless inbox_ids.include?(@inbox.id)
    return if @processed_mail.auto_reply?

    days = ENV.fetch('EMAIL_THREAD_BY_CONTACT_DAYS', '14').to_i
    conversation = @contact.conversations.where(inbox: @inbox)
                           .where('last_activity_at > ?', days.days.ago)
                           .order(last_activity_at: :desc).first
    Rails.logger.info("EmailThreadByContact: mail #{@processed_mail.message_id} -> conversation #{conversation.display_id}") if conversation
    conversation
  end
end

Rails.application.config.to_prepare do
  Imap::ImapMailbox.prepend(EmailThreadByContact) unless Imap::ImapMailbox <= EmailThreadByContact
end
