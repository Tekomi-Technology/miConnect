require 'rails_helper'

RSpec.describe Voice::VoipPushJob do
  let(:call) { create(:call) }
  let(:service) { instance_double(Voice::VoipPushService, deliver_incoming: nil, deliver_cancel: nil) }

  before { allow(Voice::VoipPushService).to receive(:new).and_return(service) }

  it 'does nothing while APNs is not configured' do
    allow(Voice::ApnsVoipClient).to receive(:configured?).and_return(false)
    described_class.perform_now(call.id, 'incoming')
    expect(Voice::VoipPushService).not_to have_received(:new)
  end

  context 'when configured' do
    before { allow(Voice::ApnsVoipClient).to receive(:configured?).and_return(true) }

    it 'sends the incoming push while the call is ringing' do
      described_class.perform_now(call.id, 'incoming')
      expect(service).to have_received(:deliver_incoming)
    end

    it 'skips the incoming push when the call is no longer ringing' do
      call.update!(status: 'in_progress')
      described_class.perform_now(call.id, 'incoming')
      expect(service).not_to have_received(:deliver_incoming)
    end

    it 'sends the cancel push' do
      described_class.perform_now(call.id, 'cancel')
      expect(service).to have_received(:deliver_cancel)
    end
  end
end
