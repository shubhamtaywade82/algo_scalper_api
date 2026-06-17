# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dev::FreshStart do
  describe '.call' do
    it 'refuses outside development' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      expect { described_class.call }.to raise_error(Dev::FreshStart::Error, /development/)
    end
  end
end
