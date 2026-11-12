require 'rails_helper'

RSpec.describe ZaloOa::BackfillJob do
  let(:account) { create(:account) }
  let(:channel) do
    Channel::ZaloOa.create!(
      account: account, oa_id: 'oa-1', app_id: 'app', app_secret: 'secret', oa_secret_key: 'key',
      access_token: 'token', refresh_token: 'refresh', token_expires_at: 1.hour.from_now
    )
  end
  let(:blocked_key) { format(Redis::Alfred::ZALO_OA_BACKFILL_BLOCKED, channel_id: channel.id) }
  let(:tier_error) do
    ZaloOa::Client::Error.new('request failed: -224 The OA needs to upgrade OA Tier Package', code: -224)
  end

  before do
    Inbox.create!(account: account, channel: channel, name: 'Zalo OA')
    Redis::Alfred.delete(blocked_key)
  end

  after { Redis::Alfred.delete(blocked_key) }

  describe 'permanent Zalo error (-224)' do
    before { allow(ZaloOa::Client).to receive(:list_recent_chats).and_raise(tier_error) }

    it 'does not raise, so the job is not retried or sent to the dead set' do
      expect { described_class.perform_now(channel.id) }.not_to raise_error
    end

    it 'pauses the channel and skips Zalo calls until the pause expires' do
      described_class.perform_now(channel.id)
      expect(Redis::Alfred.get(blocked_key)).to eq('-224')

      described_class.perform_now(channel.id)
      expect(ZaloOa::Client).to have_received(:list_recent_chats).once
    end
  end

  describe 'transient error' do
    it 'is retried with backoff instead of being raised' do
      allow(ZaloOa::Client).to receive(:list_recent_chats).and_raise(ZaloOa::Client::Error.new('status 502'))

      expect { described_class.perform_now(channel.id) }.to have_enqueued_job(described_class).with(channel.id)
      expect(Redis::Alfred.get(blocked_key)).to be_nil
    end

    it 'gives up quietly after the retry attempts are exhausted' do
      allow(ZaloOa::Client).to receive(:list_recent_chats).and_raise(SocketError, 'getaddrinfo failed')
      job = described_class.new(channel.id)
      job.executions = 3

      expect { job.perform_now }.not_to raise_error
      expect(Redis::Alfred.get(blocked_key)).to be_nil
    end
  end
end

RSpec.describe ZaloOa::Client::Error do
  it 'flags -224 as permanent and unknown codes as transient' do
    expect(described_class.new('x', code: -224)).to be_permanent
    expect(described_class.new('x', code: -2)).not_to be_permanent
    expect(described_class.new('x')).not_to be_permanent
  end
end
