# frozen_string_literal: true

require 'rails_helper'

# Every cross-service contract fixture must validate against its schema; options-trading-agent runs the
# same fixtures through its own validator, so a broken fixture fails both repos.
RSpec.describe Contracts::Schema do
  def base_names(pattern, suffix)
    Rails.root.glob(pattern).map { |path| path.basename.to_s.delete_suffix(suffix) }
  end

  it 'has a fixture for every schema' do
    expect(base_names('contracts/fixtures/*.example.json', '.example.json'))
      .to match_array(base_names('contracts/schemas/*.schema.json', '.schema.json'))
  end

  Rails.root.glob('contracts/fixtures/*.example.json').each do |path|
    it "validates the #{path.basename} fixture" do
      expect(described_class.errors(path.basename.to_s.delete_suffix('.example.json'), JSON.parse(path.read))).to be_empty
    end
  end

  it 'reports errors for a non-conforming payload' do
    expect(described_class.errors('intent-outcome-1', { 'schema' => 'intent-outcome/1' })).not_to be_empty
  end
end
