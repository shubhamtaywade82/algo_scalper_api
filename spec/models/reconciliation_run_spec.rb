# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReconciliationRun do
  describe 'validations' do
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
    it { is_expected.to validate_inclusion_of(:mode).in_array(described_class::MODES) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:discrepancies).dependent(:destroy) }
  end

  describe '#complete!' do
    it 'sets status and completed_at' do
      run = create(:reconciliation_run)
      run.complete!('passed')
      expect(run.status).to eq('passed')
      expect(run.completed_at).to be_present
    end
  end
end
