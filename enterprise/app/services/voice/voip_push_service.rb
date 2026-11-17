# Wakes the mobile app for a call: PushKit VoIP push to every iOS device of the people who can take the call.
# iOS requires the app to report each VoIP push to CallKit, so a cancel push is sent when the call stops ringing.
class Voice::VoipPushService
  def initialize(call, client: Voice::ApnsVoipClient.new)
    @call = call
    @client = client
  end

  def deliver_incoming
    deliver(incoming_payload)
  end

  def deliver_cancel
    deliver(incoming_payload.merge(type: 'voice_call.cancel', status: @call.display_status, reason: @call.end_reason))
  end

  private

  def deliver(payload)
    subscriptions.each do |subscription|
      token = subscription.subscription_attributes['push_token']
      next if token.blank?

      result = @client.deliver(token, payload)
      handle_failure(subscription, result) unless result.success?
    end
  end

  def handle_failure(subscription, result)
    if result.invalid_token?
      subscription.destroy
      Rails.logger.info("apns_voip: removed dead token for user #{subscription.user_id} (#{result.status} #{result.reason})")
    else
      Rails.logger.warn("apns_voip: push failed for user #{subscription.user_id} (#{result.status} #{result.reason})")
    end
  end

  # Same audience as the ringing dashboard: inbox members plus roles that see every inbox.
  def subscriptions
    account = @call.account
    user_ids = (@call.inbox.members.pluck(:id) + account.full_conversation_access_users.pluck(:id)).uniq
    NotificationSubscription.apns_voip.where(user_id: user_ids)
  end

  def incoming_payload
    {
      type: 'voice_call.incoming',
      id: @call.id,
      call_id: @call.provider_call_id,
      provider: @call.provider,
      conversation_id: @call.conversation_id,
      inbox_id: @call.inbox_id,
      inbox_name: @call.inbox.name,
      account_id: @call.account_id,
      caller: { name: @call.contact&.name, phone: @call.contact&.phone_number }
    }
  end
end
