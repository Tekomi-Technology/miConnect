class Voice::VoipPushJob < ApplicationJob
  queue_as :critical

  # A ringing push that arrives after the call ended only makes the phone flash a ghost call: retry briefly, never long.
  retry_on Voice::ApnsVoipClient::ConnectionError, wait: 1.second, attempts: 2

  def perform(call_id, kind)
    return unless Voice::ApnsVoipClient.configured?

    call = Call.find_by(id: call_id)
    return if call.blank?

    service = Voice::VoipPushService.new(call)
    case kind.to_s
    when 'incoming' then service.deliver_incoming if call.ringing?
    when 'cancel' then service.deliver_cancel
    end
  end
end
