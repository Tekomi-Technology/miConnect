# Distributed tracing (Grafana Tempo via OTLP). Does NOTHING unless OTEL_EXPORTER_OTLP_ENDPOINT is set.
#
#   OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4318
#   OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
#   OTEL_TRACES_SAMPLER_ARG=0.1        # sample ratio for new root traces (default 0.1)
#
# Not to be confused with lib/opentelemetry_config.rb (Langfuse LLM tracing, configured lazily from InstallationConfig).
if ENV['OTEL_EXPORTER_OTLP_ENDPOINT'].present?
  begin
    require 'opentelemetry/sdk'
    require 'opentelemetry/exporter/otlp'
    require 'opentelemetry/instrumentation/rack'
    require 'opentelemetry/instrumentation/action_pack'
    require 'opentelemetry/instrumentation/pg'
    require 'opentelemetry/instrumentation/redis'
    require 'opentelemetry/instrumentation/net/http'
    require 'opentelemetry/instrumentation/sidekiq'

    # Defaults tuned for a RAM-tight host; every value can still be overridden through the standard OTEL_* env vars.
    ENV['OTEL_TRACES_EXPORTER'] ||= 'otlp'
    ENV['OTEL_TRACES_SAMPLER'] ||= 'parentbased_traceidratio'
    ENV['OTEL_TRACES_SAMPLER_ARG'] ||= '0.1'
    ENV['OTEL_BSP_MAX_QUEUE_SIZE'] ||= '512'
    ENV['OTEL_BSP_MAX_EXPORT_BATCH_SIZE'] ||= '128'
    ENV['OTEL_BSP_SCHEDULE_DELAY'] ||= '5000'
    ENV['OTEL_BSP_EXPORT_TIMEOUT'] ||= '10000'
    # Metrics/logs are not used; avoid pulling their SDKs.
    ENV['OTEL_METRICS_EXPORTER'] ||= 'none'
    ENV['OTEL_LOGS_EXPORTER'] ||= 'none'

    OpenTelemetry::SDK.configure do |c|
      c.service_name = Sidekiq.server? ? 'chatwoot-sidekiq' : 'chatwoot-rails'
      c.use 'OpenTelemetry::Instrumentation::Rack', untraced_endpoints: ['/health', '/up']
      c.use 'OpenTelemetry::Instrumentation::ActionPack'
      c.use 'OpenTelemetry::Instrumentation::PG', db_statement: :obfuscate
      c.use 'OpenTelemetry::Instrumentation::Redis', db_statement: :obfuscate
      c.use 'OpenTelemetry::Instrumentation::Net::HTTP'
      c.use 'OpenTelemetry::Instrumentation::Sidekiq'
    end
  rescue StandardError, LoadError => e
    Rails.logger.error("OpenTelemetry tracing disabled: #{e.class} #{e.message}")
  end
end
