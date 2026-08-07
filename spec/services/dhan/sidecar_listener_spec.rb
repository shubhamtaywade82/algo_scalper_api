# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::SidecarListener do
  describe '.process_fill' do
    it 'handles fill events cleanly' do
      payload = {
        'correlation_id' => 'CORR_TEST',
        'is_paper' => true,
        'fill_price' => 125.5,
        'quantity' => 50
      }

      expect do
        described_class.send(:process_fill, payload)
      end.not_to raise_error
    end
  end

  describe '.process_exit' do
    it 'handles exit events cleanly' do
      payload = {
        'correlation_id' => 'CORR_TEST',
        'is_paper' => true,
        'exit_price' => 140.0,
        'pnl' => 725.0,
        'reason' => 'target_hit'
      }

      expect do
        described_class.send(:process_exit, payload)
      end.not_to raise_error
    end
  end
end
