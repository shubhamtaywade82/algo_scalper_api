# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImporter do
  let(:header) { 'EXCH_ID,SEGMENT,SECURITY_ID,UNDERLYING_SECURITY_ID,SYMBOL_NAME,DISPLAY_NAME,INSTRUMENT,SM_EXPIRY_DATE,STRIKE_PRICE,OPTION_TYPE,LOT_SIZE' }
  let(:expiry) { 1.month.from_now.to_date }

  def option_row(security_id)
    "NSE,D,#{security_id},25844,HYUNDAI,HYUNDAI 2880 CALL,OPTSTK,#{expiry},2880,CE,300"
  end

  def live_contract(security_id)
    create(:instrument, security_id: security_id, underlying_security_id: '25844', expiry_date: expiry,
                        strike_price: 2880, option_type: 'CE', instrument_type: 'OPTSTK')
  end

  it 'skips rows whose segment code the enum does not know' do
    csv = [header, 'NSE,G,999,,GOLDX,GOLDX,OTHER,,,,1', option_row('37316')].join("\n")

    expect { described_class.import_from_csv(csv) }.not_to raise_error
    expect(Instrument.find_by(security_id: '999')).to be_nil
  end

  it 'moves a reissued contract to its new security id instead of colliding' do
    contract = live_contract('100412')

    described_class.import_from_csv([header, option_row('37316')].join("\n"))

    expect(contract.reload.security_id).to eq('37316')
  end

  it 'retires an expired contract whose security id Dhan recycled' do
    contract = live_contract('100412')
    expired = create(:instrument, security_id: '37316', expiry_date: 2.months.ago, instrument_type: 'OPTSTK',
                                  strike_price: 265, option_type: 'PE')

    described_class.import_from_csv([header, option_row('37316')].join("\n"))

    expect(contract.reload.security_id).to eq('37316')
    expect(expired.reload.security_id).to eq("37316:retired:#{expired.id}")
  end
end
