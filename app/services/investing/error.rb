# frozen_string_literal: true

module Investing
  # Base class for every typed Investing-domain error (TDD §6 preamble).
  # Services raise subclasses — never bare StandardError — mirroring the
  # app/domain/errors.rb conventions of the Trading domain.
  class Error < StandardError; end
end
