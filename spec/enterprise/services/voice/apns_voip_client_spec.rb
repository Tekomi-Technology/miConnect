require 'rails_helper'

RSpec.describe Voice::ApnsVoipClient do
  let(:key_file) do
    Tempfile.new(['AuthKey', '.p8']).tap do |f|
      f.write(OpenSSL::PKey::EC.generate('prime256v1').to_pem)
      f.flush
    end
  end
  let(:token) { 'a' * 64 }
  let(:payload) { { type: 'voice_call.incoming', call_id: 'CA1' } }

  before do
    stub_const('ENV', ENV.to_hash.merge('APNS_KEY_PATH' => key_file.path, 'APNS_KEY_ID' => 'KEYID12345',
                                        'APNS_TEAM_ID' => 'TEAMID1234'))
    described_class.reset_token_cache!
  end

  describe '.configured?' do
    it 'is true with key file, key id and team id' do
      expect(described_class).to be_configured
    end

    it 'is false when the key file is missing' do
      stub_const('ENV', ENV.to_hash.merge('APNS_KEY_PATH' => '/nonexistent.p8'))
      expect(described_class).not_to be_configured
    end
  end

  describe '#deliver' do
    it 'posts a voip push with the topic, push type and an ES256 provider token' do
      stub = stub_request(:post, "https://api.push.apple.com/3/device/#{token}")
             .with(headers: { 'apns-topic' => 'vn.tekomi.chat.voip', 'apns-push-type' => 'voip', 'apns-priority' => '10' }) do |req|
        jwt = req.headers['Authorization'].split.last
        _, header = JWT.decode(jwt, nil, false)
        header['alg'] == 'ES256' && header['kid'] == 'KEYID12345' && req.body.include?('"call_id":"CA1"')
      end.to_return(status: 200, body: '')

      result = described_class.new.deliver(token, payload)

      expect(stub).to have_been_requested
      expect(result).to be_success
    end

    it 'treats 410 as an invalid token' do
      stub_request(:post, "https://api.push.apple.com/3/device/#{token}").to_return(status: 410, body: '{"reason":"Unregistered"}')
      result = described_class.new.deliver(token, payload)
      expect(result).to be_invalid_token
    end

    it 'falls back to the sandbox when production says BadDeviceToken' do
      stub_request(:post, "https://api.push.apple.com/3/device/#{token}").to_return(status: 400, body: '{"reason":"BadDeviceToken"}')
      stub_request(:post, "https://api.sandbox.push.apple.com/3/device/#{token}").to_return(status: 200, body: '')
      result = described_class.new.deliver(token, payload)
      expect(result).to be_success
      expect(result.environment).to eq('sandbox')
    end

    it 'reports an invalid token when both environments reject it' do
      stub_request(:post, %r{https://api\.(sandbox\.)?push\.apple\.com/3/device/.*}).to_return(status: 400, body: '{"reason":"BadDeviceToken"}')
      expect(described_class.new.deliver(token, payload)).to be_invalid_token
    end

    it 'does not treat a throttling or server error as an invalid token' do
      stub_request(:post, "https://api.push.apple.com/3/device/#{token}").to_return(status: 429, body: '{"reason":"TooManyRequests"}')
      result = described_class.new.deliver(token, payload)
      expect(result).not_to be_success
      expect(result).not_to be_invalid_token
    end
  end
end
