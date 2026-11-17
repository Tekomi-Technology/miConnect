# Sends iOS PushKit (VoIP) pushes through APNs over HTTP/2 with token-based auth (.p8 key).
#
#   APNS_KEY_PATH   path to the AuthKey_XXXX.p8 file (mounted as a secret, never stored in the repo)
#   APNS_KEY_ID     10-char key id
#   APNS_TEAM_ID    10-char Apple team id
#   APNS_VOIP_TOPIC bundle id + ".voip" (default vn.tekomi.chat.voip)
#
# Does nothing (configured? == false) until all three required values are present.
class Voice::ApnsVoipClient
  PRODUCTION_URL = 'https://api.push.apple.com'.freeze
  SANDBOX_URL = 'https://api.sandbox.push.apple.com'.freeze
  DEFAULT_TOPIC = 'vn.tekomi.chat.voip'.freeze
  JWT_TTL = 40.minutes # APNs accepts a provider token for at most 60 minutes and rejects refreshes more often than every 20.

  Result = Struct.new(:status, :reason, :environment) do
    def success?
      status == 200
    end

    # The token will never work again for this app: drop the subscription.
    def invalid_token?
      status == 410 || (status == 400 && %w[BadDeviceToken DeviceTokenNotForTopic].include?(reason))
    end
  end

  class ConnectionError < StandardError; end

  JWT_MUTEX = Mutex.new

  class << self
    def configured?
      ENV['APNS_KEY_PATH'].present? && ENV['APNS_KEY_ID'].present? && ENV['APNS_TEAM_ID'].present? &&
        File.readable?(ENV['APNS_KEY_PATH'])
    end

    def reset_token_cache!
      JWT_MUTEX.synchronize { @jwt = nil }
    end

    def provider_token
      JWT_MUTEX.synchronize do
        @jwt = nil if @jwt && @jwt[:expires_at] <= Time.current
        @jwt ||= build_token
        @jwt[:value]
      end
    end

    private

    def build_token
      key = OpenSSL::PKey::EC.new(File.read(ENV.fetch('APNS_KEY_PATH')))
      value = JWT.encode({ iss: ENV.fetch('APNS_TEAM_ID'), iat: Time.current.to_i }, key, 'ES256', { kid: ENV.fetch('APNS_KEY_ID') })
      { value: value, expires_at: JWT_TTL.from_now }
    end
  end

  # TestFlight / App Store builds use production tokens; Xcode debug builds use sandbox tokens. The app does not say
  # which one it is, so a production "BadDeviceToken" is retried against the sandbox before the token is declared dead.
  def deliver(device_token, payload)
    result = post(PRODUCTION_URL, device_token, payload, 'production')
    return result unless result.status == 400 && result.reason == 'BadDeviceToken'

    sandbox = post(SANDBOX_URL, device_token, payload, 'sandbox')
    sandbox.success? ? sandbox : result
  end

  private

  def post(base_url, device_token, payload, environment)
    response = HTTPX.with(timeout: { connect_timeout: 5, request_timeout: 10 }).post(
      "#{base_url}/3/device/#{device_token}",
      headers: headers,
      body: payload.to_json
    )
    raise ConnectionError, response.error.message if response.is_a?(HTTPX::ErrorResponse)

    Result.new(response.status, parse_reason(response), environment)
  end

  def headers
    {
      'authorization' => "bearer #{self.class.provider_token}",
      'apns-topic' => ENV.fetch('APNS_VOIP_TOPIC', DEFAULT_TOPIC),
      'apns-push-type' => 'voip',
      'apns-priority' => '10',
      'apns-expiration' => '0', # never queue: a stale "incoming call" push is worse than none
      'content-type' => 'application/json'
    }
  end

  def parse_reason(response)
    JSON.parse(response.body.to_s)['reason']
  rescue JSON::ParserError
    nil
  end
end
