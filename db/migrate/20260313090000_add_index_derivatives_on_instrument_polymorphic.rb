# frozen_string_literal: true

class AddIndexDerivativesOnInstrumentPolymorphic < ActiveRecord::Migration[8.0]
  def change
    add_index :derivatives,
              %i[instrument_id instrument_type],
              name: "index_derivatives_on_instrument_id_and_instrument_type"
  end
end

