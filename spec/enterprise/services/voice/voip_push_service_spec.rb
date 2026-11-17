require 'rails_helper'

RSpec.describe Voice::VoipPushService do
  let(:call) { create(:call) }
  let(:account) { call.account }
  let(:inbox) { call.inbox }
  let(:client) { instance_double(Voice::ApnsVoipClient) }
  let(:ok) { Voice::ApnsVoipClient::Result.new(200, nil, 'production') }

  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:outsider) { create(:user, account: account, role: :agent) }

  def voip_subscription(user, token)
    create(:notification_subscription, user: user, identifier: "voip-#{token}", subscription_type: 'apns_voip',
                                       subscription_attributes: { push_token: token })
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    voip_subscription(agent, 'agent-token')
    voip_subscription(admin, 'admin-token')
    voip_subscription(outsider, 'outsider-token')
    create(:notification_subscription, user: agent, identifier: 'fcm-1', subscription_type: 'fcm',
                                       subscription_attributes: { push_token: 'fcm-token' })
  end

  it 'pushes to inbox members and full-access roles only, and only to apns_voip devices' do
    allow(client).to receive(:deliver).and_return(ok)

    described_class.new(call, client: client).deliver_incoming

    expect(client).to have_received(:deliver).with('agent-token', hash_including(type: 'voice_call.incoming', call_id: call.provider_call_id))
    expect(client).to have_received(:deliver).with('admin-token', anything)
    expect(client).not_to have_received(:deliver).with('outsider-token', anything)
    expect(client).not_to have_received(:deliver).with('fcm-token', anything)
  end

  it 'sends a cancel push carrying the end status' do
    call.update!(status: 'no_answer', end_reason: 'timeout')
    allow(client).to receive(:deliver).and_return(ok)

    described_class.new(call, client: client).deliver_cancel

    expect(client).to have_received(:deliver).with('agent-token', hash_including(type: 'voice_call.cancel', status: 'no-answer'))
  end

  it 'removes a subscription whose token APNs reports dead, and keeps the others' do
    allow(client).to receive(:deliver) do |token, _|
      token == 'agent-token' ? Voice::ApnsVoipClient::Result.new(410, 'Unregistered', 'production') : ok
    end

    expect { described_class.new(call, client: client).deliver_incoming }
      .to change { NotificationSubscription.apns_voip.where(identifier: 'voip-agent-token').count }.from(1).to(0)
    expect(NotificationSubscription.apns_voip.where(identifier: 'voip-admin-token')).to exist
  end

  it 'keeps the subscription on a transient failure' do
    allow(client).to receive(:deliver).and_return(Voice::ApnsVoipClient::Result.new(503, 'ServiceUnavailable', 'production'))
    expect { described_class.new(call, client: client).deliver_incoming }.not_to(change(NotificationSubscription, :count))
  end
end
