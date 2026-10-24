# frozen_string_literal: true

# Raise the soft open-file limit so long-running processes (trading daemon,
# Puma, Solid Queue) don't hit EMFILE during peak HTTP/WebSocket activity.
# The hard limit is typically already 1M on Linux; only the soft limit needs
# bumping. Override with MAX_OPEN_FILES.
begin
  if Process.respond_to?(:setrlimit)
    soft, hard = Process.getrlimit(:NOFILE)
    desired = [ENV.fetch('MAX_OPEN_FILES', '65535').to_i, hard].min
    Process.setrlimit(:NOFILE, [desired, soft].max, hard) if soft < desired
  end
rescue StandardError => e
  warn "[Startup] Could not raise NOFILE limit: #{e.message}"
end