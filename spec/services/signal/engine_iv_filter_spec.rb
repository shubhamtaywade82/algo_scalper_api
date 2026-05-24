# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Signal::Engine real IV filter' do
  describe '.validate_iv_rank_real' do
    let(:mode_config) { { iv_rank_min: 0.10, iv_rank_max: 0.75 } }

    context 'IV data is zero or nil (unavailable)' do
      it 'passes through (fail-open)' do
        result = Signal::Engine.send(:validate_iv_rank_real, 0.0, mode_config)
        expect(result[:valid]).to be true
      end
    end

    context 'IV is 0.50 (within range)' do
      it 'passes' do
        result = Signal::Engine.send(:validate_iv_rank_real, 0.50, mode_config)
        expect(result[:valid]).to be true
      end
    end

    context 'IV is 0.82 (above max — pre-event spike)' do
      it 'blocks the entry' do
        result = Signal::Engine.send(:validate_iv_rank_real, 0.82, mode_config)
        expect(result[:valid]).to be false
        expect(result[:reason]).to include('IV too high')
      end
    end

    context 'IV is 0.05 (below min — dead market)' do
      it 'blocks the entry' do
        result = Signal::Engine.send(:validate_iv_rank_real, 0.05, mode_config)
        expect(result[:valid]).to be false
        expect(result[:reason]).to include('IV too low')
      end
    end

    context 'IV exactly at max (0.75)' do
      it 'passes (boundary — not strictly above max)' do
        result = Signal::Engine.send(:validate_iv_rank_real, 0.75, mode_config)
        expect(result[:valid]).to be true
      end
    end
  end
end
