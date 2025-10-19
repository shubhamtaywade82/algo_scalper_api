# frozen_string_literal: true

module Api
  class AtmOptionsController < ApplicationController
    def index
      atm_service = Live::AtmOptionsService.instance

      if atm_service.running?
        # Return the current ATM options data
        options_data = {}

        # Get ATM options for each index
        [ "NIFTY", "BANKNIFTY", "SENSEX" ].each do |index_key|
          call_option = atm_service.get_atm_option(index_key, :call)
          put_option = atm_service.get_atm_option(index_key, :put)

          if call_option && put_option
            options_data[index_key] = {
              call: {
                segment: call_option[:segment],
                security_id: call_option[:security_id],
                strike: call_option[:strike],
                expiry: call_option[:expiry]
              },
              put: {
                segment: put_option[:segment],
                security_id: put_option[:security_id],
                strike: put_option[:strike],
                expiry: put_option[:expiry]
              },
              current_ltp: call_option[:current_ltp],
              expiry: call_option[:expiry]
            }
          end
        end

        render json: options_data
      else
        render json: { error: "ATM options service not running" }, status: :service_unavailable
      end
    end
  end
end
