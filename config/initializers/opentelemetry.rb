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

  # Plain-text Rails.logger lines (ActiveJob/Sidekiq "Performed ...", errors, ...) get a ` trace_id=<hex>` suffix while a
  # span is active, so Alloy can store it as Loki structured metadata and Grafana can link the line to its trace.
  # Lograge JSON lines already carry trace_id and are left untouched (Alloy parses them as JSON).
  module TraceIdLogSuffix
    def call(severity, timestamp, progname, msg)
      line = super
      return line if line.include?('"trace_id"')

      ctx = OpenTelemetry::Trace.current_span.context
      return line unless ctx.valid? && ctx.trace_flags.sampled?

      line.sub(/\n\z/, " trace_id=#{ctx.hex_trace_id}\n")
    rescue StandardError
      line
    end
  end

  Rails.application.config.after_initialize do
    Rails.logger.formatter&.extend(TraceIdLogSuffix)
  end
end
