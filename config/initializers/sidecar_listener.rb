# frozen_string_literal: true

# Start Redis listener for DhanHQ-TS sidecar execution fills and exits.
Rails.application.config.after_initialize do
  unless Rails.env.test?
    Dhan::SidecarListener.start!
  end
end
