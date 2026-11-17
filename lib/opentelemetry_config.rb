require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'base64'

module OpentelemetryConfig
  class << self
    def tracer
      initialize! unless initialized?
      (@provider || OpenTelemetry.tracer_provider).tracer('chatwoot')
    end

    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized
      return mark_initialized unless langfuse_provider?
      return mark_initialized unless langfuse_credentials_present?

      configure_opentelemetry
      mark_initialized
    rescue StandardError => e
      Rails.logger.error "Failed to configure OpenTelemetry: #{e.message}"
      mark_initialized
    end

    def reset!
      @initialized = false
      @provider = nil
    end

    private

    def mark_initialized
      @initialized = true
    end

    def langfuse_provider?
      otel_provider = InstallationConfig.find_by(name: 'OTEL_PROVIDER')&.value
      otel_provider == 'langfuse'
    end

    def langfuse_credentials_present?
      endpoint = InstallationConfig.find_by(name: 'LANGFUSE_BASE_URL')&.value
      public_key = InstallationConfig.find_by(name: 'LANGFUSE_PUBLIC_KEY')&.value
      secret_key = InstallationConfig.find_by(name: 'LANGFUSE_SECRET_KEY')&.value

      if endpoint.blank? || public_key.blank? || secret_key.blank?
        Rails.logger.error 'OpenTelemetry disabled (LANGFUSE_BASE_URL, LANGFUSE_PUBLIC_KEY or LANGFUSE_SECRET_KEY is missing)'
        return false
      end

      true
    end

    def langfuse_credentials
      {
        endpoint: InstallationConfig.find_by(name: 'LANGFUSE_BASE_URL')&.value,
        public_key: InstallationConfig.find_by(name: 'LANGFUSE_PUBLIC_KEY')&.value,
        secret_key: InstallationConfig.find_by(name: 'LANGFUSE_SECRET_KEY')&.value
      }
    end

    def traces_endpoint
      credentials = langfuse_credentials
      "#{credentials[:endpoint]}/api/public/otel/v1/traces"
    end

    def exporter_config
      credentials = langfuse_credentials
      auth_header = Base64.strict_encode64("#{credentials[:public_key]}:#{credentials[:secret_key]}")

      config = {
        endpoint: traces_endpoint,
        headers: {
          'Authorization' => "Basic #{auth_header}",
          'x-langfuse-ingestion-version' => '4'
        }
      }

      config[:ssl_verify_mode] = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?
      config
    end

    def configure_opentelemetry
      exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(**exporter_config)
      processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)

      if tempo_tracing_enabled?
        # config/initializers/opentelemetry.rb already owns the global provider (Tempo). Configuring it again would
        # replace it and ship every HTTP/DB span to Langfuse, so LLM spans get a private provider instead. ALWAYS_ON:
        # the Tempo head sampler must not drop LLM generations.
        @provider = OpenTelemetry::SDK::Trace::TracerProvider.new(
          resource: OpenTelemetry::SDK::Resources::Resource.create('service.name' => 'chatwoot'),
          sampler: OpenTelemetry::SDK::Trace::Samplers::ALWAYS_ON
        )
        @provider.add_span_processor(processor)
      else
        OpenTelemetry::SDK.configure do |c|
          c.service_name = 'chatwoot'
          c.add_span_processor(processor)
        end
      end
      Rails.logger.info 'OpenTelemetry initialized and configured to export to Langfuse'
    end

    def tempo_tracing_enabled?
      ENV['OTEL_EXPORTER_OTLP_ENDPOINT'].present?
    end
  end
end
