# frozen_string_literal: true

module Strategies
  # Checksum-verified strategy loader.
  #
  # Reads the file at the version's +file_path+, verifies SHA-256 against
  # the stored checksum, then +load+s the file into an anonymous module
  # wrapper for constant tracking. The loaded class is registered in
  # +Strategies::Runtime+ for cleanup on hot-reload.
  #
  # See docs/infra-strategy-setup/04_strategy_plugin_system.md#loading--reloading
  class Loader
    class ChecksumMismatch < StandardError; end
    class ClassNotFound < StandardError; end

    attr_reader :version, :class_name

    def initialize(version)
      @version = version
      manifest = version.manifest
      @class_name = manifest["class_name"]
    end

    def load
      content = read_and_verify

      mod = Module.new
      mod.module_eval(content, version.file_path)

      unless mod.const_defined?(@class_name)
        raise ClassNotFound, "#{@class_name} not defined in #{version.file_path}"
      end

      strategy_class = mod.const_get(@class_name)

      Runtime.register(@class_name, strategy_class, mod)

      strategy_class
    end

    def self.load_version(version)
      new(version).load
    end

    private

    def read_and_verify
      path = version.file_path
      content = File.read(path)
      actual = Digest::SHA256.hexdigest(content)
      stored = version.checksum

      unless ActiveSupport::SecurityUtils.secure_compare(actual, stored)
        raise ChecksumMismatch,
              "SHA-256 mismatch for #{path}: expected #{stored}, got #{actual}"
      end

      content
    end
  end

  # Runtime registry for strategy classes loaded via {Loader}.
  # Enables constant cleanup on hot-reload.
  module Runtime
    @registry = {}
    @mutex = Mutex.new

    module_function

    def register(class_name, strategy_class, mod)
      @mutex.synchronize do
        @registry[class_name] = { class: strategy_class, mod: mod }
      end
    end

    def lookup(class_name)
      @mutex.synchronize { @registry.dig(class_name, :class) }
    end

    def remove(class_name)
      @mutex.synchronize do
        entry = @registry.delete(class_name)
        return unless entry

        mod = entry[:mod]
        mod.constants.each { |c| mod.send(:remove_const, c) }
        Object.send(:remove_const, class_name) if Object.const_defined?(class_name, false)
      end
    end
  end
end
