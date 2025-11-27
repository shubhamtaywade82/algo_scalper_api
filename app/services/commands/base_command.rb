# frozen_string_literal: true

module Commands
  # Base class for command pattern implementation
  # Provides audit trail, retry logic, and undo capability
  class BaseCommand
    attr_reader :command_id, :created_at, :executed_at, :status, :error_message, :metadata

    def initialize(metadata: {})
      @command_id = SecureRandom.uuid
      @created_at = Time.current
      @executed_at = nil
      @status = :pending
      @error_message = nil
      @metadata = metadata
      @retry_count = 0
      @max_retries = 3
    end

    # Execute the command
    # @return [Hash] Result hash with :success, :data, :error
    def execute
      return failure_result('Command already executed') if executed?

      @status = :executing
      log_command_start

      result = perform_execution

      if result[:success]
        @status = :completed
        @executed_at = Time.current
        log_command_success(result)
        audit_log(:success, result)
      else
        handle_execution_failure(result)
      end

      result
    rescue StandardError => e
      handle_exception(e)
    end

    # Retry execution with exponential backoff
    # @return [Hash] Result hash
    def retry
      return failure_result('Max retries exceeded') if @retry_count >= @max_retries

      @retry_count += 1
      delay = calculate_backoff_delay(@retry_count)
      sleep(delay)

      Rails.logger.info("[Commands::BaseCommand] Retrying command #{@command_id} (attempt #{@retry_count}/#{@max_retries})")
      execute
    end

    # Undo the command (if supported)
    # @return [Hash] Result hash
    def undo
      return failure_result('Command not executed') unless executed?
      return failure_result('Undo not supported') unless undoable?

      @status = :undoing
      result = perform_undo

      if result[:success]
        @status = :undone
        log_command_undo(result)
        audit_log(:undo, result)
      else
        Rails.logger.error("[Commands::BaseCommand] Undo failed for #{@command_id}: #{result[:error]}")
      end

      result
    rescue StandardError => e
      Rails.logger.error("[Commands::BaseCommand] Undo exception for #{@command_id}: #{e.class} - #{e.message}")
      failure_result(e.message)
    end

    # Check if command can be undone
    # @return [Boolean]
    def undoable?
      false # Override in subclasses
    end

    # Check if command has been executed
    # @return [Boolean]
    def executed?
      @status == :completed || @status == :failed
    end

    # Get command summary for logging
    # @return [Hash]
    def summary
      {
        command_id: @command_id,
        command_type: self.class.name,
        status: @status,
        created_at: @created_at,
        executed_at: @executed_at,
        retry_count: @retry_count,
        metadata: @metadata
      }
    end

    protected

    # Perform the actual command execution
    # Must be implemented by subclasses
    # @return [Hash] Result hash with :success, :data, :error
    def perform_execution
      raise NotImplementedError, "#{self.class} must implement #perform_execution"
    end

    # Perform undo operation
    # Must be implemented by subclasses that support undo
    # @return [Hash] Result hash
    def perform_undo
      failure_result('Undo not implemented')
    end

    private

    def handle_execution_failure(result)
      @status = :failed
      @error_message = result[:error]
      log_command_failure(result)
      audit_log(:failure, result)
    end

    def handle_exception(exception)
      @status = :failed
      @error_message = "#{exception.class}: #{exception.message}"
      Rails.logger.error("[Commands::BaseCommand] Exception in #{self.class.name}: #{exception.class} - #{exception.message}")
      Rails.logger.debug { exception.backtrace.first(10).join("\n") }
      audit_log(:exception, { error: @error_message, backtrace: exception.backtrace.first(5) })
      failure_result(@error_message)
    end

    def calculate_backoff_delay(retry_count)
      # Exponential backoff: 1s, 2s, 4s
      (2**(retry_count - 1)).to_f
    end

    def log_command_start
      Rails.logger.info("[Commands::BaseCommand] Executing #{self.class.name} (#{@command_id})")
    end

    def log_command_success(result)
      Rails.logger.info("[Commands::BaseCommand] Command #{@command_id} completed successfully")
    end

    def log_command_failure(result)
      Rails.logger.error("[Commands::BaseCommand] Command #{@command_id} failed: #{result[:error]}")
    end

    def log_command_undo(result)
      Rails.logger.info("[Commands::BaseCommand] Command #{@command_id} undone successfully")
    end

    def audit_log(event_type, data)
      # Store command audit log (could be persisted to database or cache)
      audit_data = {
        command_id: @command_id,
        command_type: self.class.name,
        event_type: event_type,
        timestamp: Time.current,
        status: @status,
        retry_count: @retry_count,
        data: data,
        metadata: @metadata
      }

      # Store in cache for now (could be moved to database table)
      cache_key = "command_audit:#{@command_id}"
      Rails.cache.write(cache_key, audit_data, expires_in: 7.days)

      # Also emit event for external systems
      Core::EventBus.instance.publish(:command_executed, audit_data)
    rescue StandardError => e
      Rails.logger.error("[Commands::BaseCommand] Audit log failed: #{e.class} - #{e.message}")
    end

    def success_result(data: nil)
      { success: true, data: data }
    end

    def failure_result(error)
      { success: false, error: error }
    end
  end
end
