# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Settings' do
  let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

  after do
    Setting.where(key: doc_key).delete_all
    AlgoConfigChangeLog.delete_all
    AlgoConfig.reset!
  end

  describe 'GET /api/settings' do
    it 'returns 200 with config' do
      get '/api/settings'
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json['config']).to be_a(Hash)
    end
  end

  describe 'PATCH /api/settings/bulk' do
    around do |example|
      prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
      ENV.delete('SETTINGS_UPDATE_TOKEN')
      example.run
    ensure
      if prior
        ENV['SETTINGS_UPDATE_TOKEN'] = prior
      else
        ENV.delete('SETTINGS_UPDATE_TOKEN')
      end
    end

    before do
      Setting.put(doc_key, { mode: 'paper', risk: { sl_pct: 0.02 } }.to_json)
      AlgoConfig.reset!
    end

    it 'replaces a permitted top-level subtree' do
      patch '/api/settings/bulk',
            params: { settings: { risk: { sl_pct: 0.03, trailing: { drawdown_pct: 0.02 } } } }
      expect(response).to have_http_status(:ok)
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('risk', 'sl_pct').to_f).to eq(0.03)
      expect(doc.dig('risk', 'trailing', 'drawdown_pct').to_f).to eq(0.02)
    end

    it 'writes api_settings_bulk change log' do
      patch '/api/settings/bulk', params: { settings: { signals: { enable_adx_filter: false } } }
      log = AlgoConfigChangeLog.order(:id).last
      expect(log.source).to eq('api_settings_bulk')
      expect(log.changed_paths).to include('/signals')
    end

    it 'returns 400 when settings param missing' do
      patch '/api/settings/bulk', params: {}
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 422 when all settings keys are filtered out' do
      patch '/api/settings/bulk', params: { settings: { bogus_key: { a: 1 } } }
      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body
      expect(json['error']).to match(/No permitted/)
    end
  end

  describe 'GET /api/settings/change_logs' do
    before do
      AlgoConfigChangeLog.create!(
        source: 'test',
        actor: 'rspec',
        request_id: nil,
        patch: { x: 1 },
        changed_paths: ['/risk'],
        metadata: {}
      )
    end

    it 'returns change logs with pagination metadata' do
      get '/api/settings/change_logs', params: { limit: 10 }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json).to include('total' => a_kind_of(Integer), 'limit' => 10, 'offset' => 0)
    end

    it 'includes source in each change log entry' do
      get '/api/settings/change_logs', params: { limit: 10 }
      json = response.parsed_body
      expect(json['change_logs'].first['source']).to eq('test')
    end

    it 'clamps limit to valid range' do
      get '/api/settings/change_logs', params: { limit: 999 }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['limit']).to eq(200)
    end
  end

  describe 'GET/PATCH /api/settings/fast_entry_mode' do
    after { Signal::FastEntryMode.reset! }

    it 'GET returns the current status' do
      get '/api/settings/fast_entry_mode'
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json['fast_entry_mode']).to include('persisted', 'effective', 'env_override')
    end

    context 'when SETTINGS_UPDATE_TOKEN is set' do
      around do |example|
        prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
        ENV['SETTINGS_UPDATE_TOKEN'] = 'test-token'
        example.run
      ensure
        if prior
          ENV['SETTINGS_UPDATE_TOKEN'] = prior
        else
          ENV.delete('SETTINGS_UPDATE_TOKEN')
        end
      end

      it 'PATCH rejects requests without the token' do
        patch '/api/settings/fast_entry_mode', params: { enabled: true }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'PATCH toggles the persisted flag with a valid token' do
        patch '/api/settings/fast_entry_mode',
              params: { enabled: true },
              headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(true)
        expect(json['fast_entry_mode']['persisted']).to be(true)
      end

      it 'PATCH toggles the persisted flag off with a valid token' do
        # as: :json ensures `enabled` arrives as a real boolean `false`, not the form-encoded
        # string "false" — this is the case where Rails' params.require(:enabled) needs its
        # explicit `value == false` special case to avoid raising ActionController::ParameterMissing
        # (false.blank? is true, so a naive `value.presence` check would otherwise reject it).
        patch '/api/settings/fast_entry_mode',
              params: { enabled: false },
              headers: { 'X-Settings-Update-Token' => 'test-token' },
              as: :json
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(true)
        expect(json['fast_entry_mode']['persisted']).to be(false)
      end
    end
  end

  describe 'POST /api/settings/update_ip' do
    context 'when SETTINGS_UPDATE_TOKEN is set' do
      around do |example|
        prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
        ENV['SETTINGS_UPDATE_TOKEN'] = 'test-token'
        example.run
      ensure
        if prior
          ENV['SETTINGS_UPDATE_TOKEN'] = prior
        else
          ENV.delete('SETTINGS_UPDATE_TOKEN')
        end
      end

      it 'rejects requests without the token' do
        post '/api/settings/update_ip'
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns a graceful error when the current IP cannot be detected' do
        allow(Dhan::IpService).to receive(:fetch_ip_info).and_return(
          { public_ipv4: 'Unknown', public_ipv6: 'Unknown', registered_ips: nil }
        )
        post '/api/settings/update_ip', headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(false)
      end

      it 'delegates to Dhan::IpService.update_ip with the detected IP' do
        allow(Dhan::IpService).to receive(:fetch_ip_info).and_return(
          { public_ipv4: '1.2.3.4', public_ipv6: 'None', registered_ips: nil }
        )
        allow(Dhan::IpService).to receive(:update_ip).with('1.2.3.4').and_return(
          { success: true, flag: 'PRIMARY' }
        )
        post '/api/settings/update_ip', headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(true)
        expect(json['flag']).to eq('PRIMARY')
      end
    end
  end

  describe 'PATCH /api/settings/deep_merge' do
    context 'when SETTINGS_UPDATE_TOKEN is set' do
      around do |example|
        prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
        ENV['SETTINGS_UPDATE_TOKEN'] = 'test-token'
        example.run
      ensure
        if prior
          ENV['SETTINGS_UPDATE_TOKEN'] = prior
        else
          ENV.delete('SETTINGS_UPDATE_TOKEN')
        end
      end

      it 'rejects requests without the token' do
        patch '/api/settings/deep_merge', params: { patch: { signals: { fast_entry_mode: { enabled: true } } } }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'applies the patch with a valid token' do
        # as: :json mirrors the real caller (SignalsSidebar.jsx sends JSON.stringify({ patch }))
        # — Signal::FastEntryMode.persisted_enabled? does a strict `== true` check, so a
        # form-encoded "true" string (as the other describe blocks in this file send) would
        # silently fail to enable the flag. This request must exercise the real wire format.
        patch '/api/settings/deep_merge',
              params: { patch: { signals: { fast_entry_mode: { enabled: true } } } },
              headers: { 'X-Settings-Update-Token' => 'test-token' },
              as: :json
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['success']).to be(true)
        doc = JSON.parse(Setting.find_by!(key: doc_key).value)
        expect(doc.dig('signals', 'fast_entry_mode', 'enabled')).to be(true)
      end

      it 'requires the patch param' do
        patch '/api/settings/deep_merge', params: {}, headers: { 'X-Settings-Update-Token' => 'test-token' }
        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 422 when the patch only targets a non-permitted top-level key' do
        patch '/api/settings/deep_merge',
              params: { patch: { dhanhq: { enable_orders: true } } },
              headers: { 'X-Settings-Update-Token' => 'test-token' },
              as: :json
        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json['error']).to include('No permitted')
      end

      # SignalsSidebar.jsx's Midday/Loss-Streak/Market-Context/Entry-Quality toggles PATCH
      # these top-level keys directly — regression coverage for the allowlist fixes that
      # briefly 422'd these previously-working dashboard controls. entry_quality was missed
      # in rounds 1-2 because it doesn't appear as a top-level key in config/algo.yml, even
      # though it's read live via AlgoConfig.fetch[:entry_quality] (see entry_quality_filter.rb).
      it 'applies patches to the dashboard Signals sidebar toggle keys' do
        nested_by_key = {
          midday_guard: { enabled: true },
          loss_streak_guard: { enabled: true },
          market_context: { gate: { enabled: true } },
          entry_quality: { gates: { block_choppy_regime: false } }
        }
        nested_by_key.each do |top_key, nested|
          patch '/api/settings/deep_merge',
                params: { patch: { top_key => nested } },
                headers: { 'X-Settings-Update-Token' => 'test-token' },
                as: :json
          expect(response).to have_http_status(:ok)
          doc = JSON.parse(Setting.find_by!(key: doc_key).value)
          expect(doc[top_key.to_s]).to be_present
        end
      end

      it 'returns 422 when the patch only targets the run_mode non-permitted key' do
        patch '/api/settings/deep_merge',
              params: { patch: { run_mode: { mode: 'live' } } },
              headers: { 'X-Settings-Update-Token' => 'test-token' },
              as: :json
        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json['error']).to include('No permitted')
      end
    end
  end
end
