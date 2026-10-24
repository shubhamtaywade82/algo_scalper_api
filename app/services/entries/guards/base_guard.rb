# frozen_string_literal: true

module Entries
  module Guards
    # Base for pipeline guards. Each guard implements .call(context) → :pass or { blocked: reason }.
    module BaseGuard
      PASS = EntryGuardPipeline::PASS
    end
  end
end
