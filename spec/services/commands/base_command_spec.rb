# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commands::BaseCommand do
  let(:command_class) do
    Class.new(Commands::BaseCommand) do
      protected

      def perform_execution
        { success: true, data: { result: 'test' } }
      end
    end
  end

  let(:command) { command_class.new(metadata: { test: true }) }

  describe '#initialize' do
    it 'sets command_id' do
      expect(command.command_id).to be_present
      expect(command.command_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'sets created_at timestamp' do
      expect(command.created_at).to be_within(1.second).of(Time.current)
    end

    it 'sets status to pending' do
      expect(command.status).to eq(:pending)
    end

    it 'stores metadata' do
      expect(command.metadata).to eq({ test: true })
    end
  end

  describe '#execute' do
    it 'executes the command successfully' do
      result = command.execute

      expect(result[:success]).to be true
      expect(result[:data][:result]).to eq('test')
    end

    it 'updates status to completed on success' do
      command.execute

      expect(command.status).to eq(:completed)
      expect(command.executed_at).to be_present
    end

    it 'creates audit log' do
      expect(Rails.cache).to receive(:write).with(
        "command_audit:#{command.command_id}",
        hash_including(
          command_id: command.command_id,
          command_type: command_class.name,
          status: :completed
        ),
        expires_in: 7.days
      )

      command.execute
    end

    it 'publishes command_executed event' do
      expect(Core::EventBus.instance).to receive(:publish).with(
        :command_executed,
        hash_including(
          command_id: command.command_id,
          event_type: :success
        )
      )

      command.execute
    end

    context 'when execution fails' do
      let(:failing_command_class) do
        Class.new(Commands::BaseCommand) do
          protected

          def perform_execution
            { success: false, error: 'Test error' }
          end
        end
      end

      let(:failing_command) { failing_command_class.new }

      it 'sets status to failed' do
        failing_command.execute

        expect(failing_command.status).to eq(:failed)
        expect(failing_command.error_message).to eq('Test error')
      end

      it 'logs failure in audit trail' do
        expect(Rails.cache).to receive(:write).with(
          "command_audit:#{failing_command.command_id}",
          hash_including(status: :failed),
          expires_in: 7.days
        )

        failing_command.execute
      end
    end

    context 'when exception is raised' do
      let(:exception_command_class) do
        Class.new(Commands::BaseCommand) do
          protected

          def perform_execution
            raise StandardError, 'Test exception'
          end
        end
      end

      let(:exception_command) { exception_command_class.new }

      it 'handles exception gracefully' do
        result = exception_command.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include('Test exception')
        expect(exception_command.status).to eq(:failed)
      end

      it 'logs exception details' do
        expect(Rails.logger).to receive(:error).with(
          match(/Exception in #{exception_command_class.name}/)
        )

        exception_command.execute
      end
    end

    context 'when command already executed' do
      it 'returns failure result' do
        command.execute
        result = command.execute

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Command already executed')
      end
    end
  end

  describe '#retry' do
    let(:retry_command_class) do
      Class.new(Commands::BaseCommand) do
        def initialize(*args, **kwargs)
          super(*args, **kwargs)
          @attempts = 0
        end

        protected

        def perform_execution
          @attempts += 1
          if @attempts < 2
            { success: false, error: 'Temporary failure' }
          else
            { success: true, data: { result: 'success' } }
          end
        end
      end
    end

    let(:retry_command) { retry_command_class.new }

    it 'retries with exponential backoff' do
      expect(retry_command).to receive(:sleep).with(1.0) # First retry: 2^0 = 1 second

      retry_command.execute # First attempt fails
      retry_command.retry # Retry succeeds
    end

    it 'increments retry count' do
      retry_command.execute
      retry_command.retry

      expect(retry_command.summary[:retry_count]).to eq(1)
    end

    it 'respects max retries' do
      failing_command_class = Class.new(Commands::BaseCommand) do
        protected

        def perform_execution
          { success: false, error: 'Always fails' }
        end
      end

      failing_command = failing_command_class.new
      failing_command.execute

      3.times { failing_command.retry }

      result = failing_command.retry
      expect(result[:success]).to be false
      expect(result[:error]).to eq('Max retries exceeded')
    end
  end

  describe '#undo' do
    it 'returns failure for non-executed command' do
      result = command.undo

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Command not executed')
    end

    it 'returns failure for non-undoable command' do
      command.execute
      result = command.undo

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Undo not supported')
    end

    context 'when command is undoable' do
      let(:undoable_command_class) do
        Class.new(Commands::BaseCommand) do
          def undoable?
            true
          end

          protected

          def perform_execution
            { success: true, data: { order_id: '123' } }
          end

          def perform_undo
            { success: true, data: { cancelled: true } }
          end
        end
      end

      let(:undoable_command) { undoable_command_class.new }

      it 'executes undo successfully' do
        undoable_command.execute
        result = undoable_command.undo

        expect(result[:success]).to be true
        expect(result[:data][:cancelled]).to be true
        expect(undoable_command.status).to eq(:undone)
      end
    end
  end

  describe '#summary' do
    it 'returns command summary' do
      summary = command.summary

      expect(summary).to include(
        command_id: command.command_id,
        command_type: command_class.name,
        status: :pending,
        metadata: { test: true }
      )
    end
  end

  describe '#executed?' do
    it 'returns false for pending command' do
      expect(command.executed?).to be false
    end

    it 'returns true after execution' do
      command.execute
      expect(command.executed?).to be true
    end
  end
end
