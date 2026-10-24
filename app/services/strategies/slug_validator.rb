# frozen_string_literal: true

module Strategies
  # Shared guard for every filesystem path built from user input.
  #
  # Strategy directories live under Rails.root/strategies/<slug> and slugs /
  # template names flow into Pathname#join, FileUtils.cp_r and dir.mkpath —
  # anything containing '/', '\' or '.' is a path-traversal vector
  # (e.g. "../../etc" or "foo.rb" escaping the strategies root).
  module SlugValidator
    FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
    MAX_LENGTH = 64

    class InvalidSlug < StandardError; end

    module_function

    # @param name [Object] candidate slug or template name
    # @param what [String] label used in the error message
    # @return [String] the validated name
    # @raise [InvalidSlug] when the name is not a plain, single-path-segment slug
    def validate!(name, what: 'slug')
      raise InvalidSlug, "Invalid #{what}: #{name.inspect}" unless valid?(name)

      name
    end

    def valid?(name)
      name.is_a?(String) &&
        name.length <= MAX_LENGTH &&
        name.match?(FORMAT)
    end
  end
end
