# frozen_string_literal: true

require 'rails_helper'
require 'rswag/specs'

RSpec.configure do |config|
  config.openapi_root = Rails.root.join('swagger').to_s

  config.openapi_specs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'Algo Scalper API',
        version: '1.0.0',
        description: <<~DESC.squish
          JSON API for the intraday options scalper. Optional auth: when `API_DASHBOARD_TOKEN` or
          `API_OPERATOR_TOKEN` is set, send `Authorization: Bearer <token>` or `X-Api-Key`.
          SMC with `ai=1` uses the operator tier when `API_OPERATOR_TOKEN` is set.
          OpenAPI is generated from RSwag request specs (`bundle exec rake rswag:specs:swaggerize`).
        DESC
      },
      paths: {
        '/api/settings/bulk' => {
          patch: {
            tags: ['Settings'],
            summary: 'Replace top-level algo overrides',
            description: 'Requires X-Settings-Update-Token when SETTINGS_UPDATE_TOKEN is set. ' \
                         'In production, SETTINGS_UPDATE_TOKEN must be configured or the server returns 503.',
            parameters: [
              {
                name: 'X-Settings-Update-Token',
                in: 'header',
                required: false,
                schema: { type: 'string' }
              }
            ],
            requestBody: {
              required: true,
              content: {
                'application/json' => {
                  schema: {
                    type: 'object',
                    required: ['settings'],
                    properties: {
                      settings: {
                        type: 'object',
                        additionalProperties: true,
                        description: 'Keys must match SettingsController::PERMITTED_SETTINGS_KEYS'
                      }
                    }
                  }
                }
              }
            },
            responses: {
              '200' => {
                description: 'Overrides stored',
                content: {
                  'application/json' => {
                    schema: {
                      type: 'object',
                      properties: {
                        success: { type: 'boolean' },
                        message: { type: 'string' }
                      }
                    }
                  }
                }
              },
              '401' => { description: 'Invalid or missing token when required' },
              '503' => { description: 'SETTINGS_UPDATE_TOKEN not configured in production' }
            }
          }
        }
      },
      servers: [
        { url: 'http://localhost:3011', description: 'Local web (see Procfile.dev / bin/rails server)' },
        { url: '/', description: 'Same origin' }
      ],
      tags: [
        { name: 'Infrastructure', description: 'Liveness and probes' },
        { name: 'Health', description: 'Cluster / feed health snapshot' },
        { name: 'Dashboard', description: 'Dashboard aggregate JSON' },
        { name: 'Positions', description: 'Open and closed positions' },
        { name: 'Signals', description: 'Trading signal history' },
        { name: 'SMC', description: 'Smart-money decision (cached candles)' },
        { name: 'Analysis', description: 'Analysis store and AI snapshot' },
        { name: 'Settings', description: 'Algo config read/update' },
        { name: 'Calibration', description: 'Calibration runs and apply' },
        { name: 'CircuitBreaker', description: 'Emergency trading halt' },
        { name: 'Risk', description: 'Drawdown guard reset' },
        { name: 'Debug', description: 'Development-oriented helpers' }
      ],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: 'opaque',
            description: 'Matches API_DASHBOARD_TOKEN or API_OPERATOR_TOKEN when configured'
          },
          apiKeyAuth: {
            type: :apiKey,
            in: :header,
            name: 'X-Api-Key',
            description: 'Same secret as Bearer token alternative'
          },
          settingsUpdateAuth: {
            type: :apiKey,
            in: :header,
            name: 'X-Settings-Update-Token',
            description: 'Required for PATCH /api/settings/bulk when SETTINGS_UPDATE_TOKEN is set; required in production.'
          },
          circuitBreakerAuth: {
            type: :apiKey,
            in: :header,
            name: 'X-Circuit-Breaker-Token',
            description: 'Must match CIRCUIT_BREAKER_TOKEN for trip/reset'
          }
        }
      },
      security: [],
      consumes: ['application/json'],
      produces: ['application/json']
    }
  }

  config.openapi_format = :yaml
end
