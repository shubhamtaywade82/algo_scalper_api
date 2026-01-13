# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::CapitalAllocator do
  describe '.max_lots' do
    it 'returns 0 for invalid inputs' do
      expect(described_class.max_lots(premium: 0, lot_size: 65, permission_cap: 2)).to eq(0)
      expect(described_class.max_lots(premium: 100, lot_size: 0, permission_cap: 2)).to eq(0)
      expect(described_class.max_lots(premium: 100, lot_size: 65, permission_cap: 0)).to eq(0)
    end

    it 'caps by ₹30,000 and permission cap' do
      # premium * lot_size = 100 * 65 = 6500; 30000/6500 = 4 lots max by capital
      expect(described_class.max_lots(premium: 100, lot_size: 65, permission_cap: 10)).to eq(4)
      expect(described_class.max_lots(premium: 100, lot_size: 65, permission_cap: 2)).to eq(2)
    end

    it 'floors lots correctly' do
      # 30000 / (518.4 * 65) = 0.89 -> 0 lots
      expect(described_class.max_lots(premium: 518.4, lot_size: 65, permission_cap: 4)).to eq(0)

      # 30000 / (315.8 * 20) = 4.75 -> 4 lots (permission cap higher)
      expect(described_class.max_lots(premium: 315.8, lot_size: 20, permission_cap: 10)).to eq(4)
    end
  end
end
