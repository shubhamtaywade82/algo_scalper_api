# frozen_string_literal: true

module Api
  class AlertsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!
    before_action :find_alert, only: %i[update destroy]

    # In-memory alert store (per-process — acceptable for dashboard visibility).
    # Lost on restart; alerts are ephemeral notifications, not durable records.
    @alerts = []
    @mutex = Mutex.new
    @next_id = 1

    class << self
      attr_reader :alerts, :mutex, :next_id

      def push_alert(type:, severity:, message:)
        mutex.synchronize do
          id = @next_id
          @next_id += 1
          alert = {
            id: id,
            type: type,
            severity: severity,
            message: message,
            read: false,
            created_at: Time.current.iso8601
          }
          @alerts.unshift(alert)
          @alerts.pop if @alerts.size > 100 # cap at 100
          alert
        end
      end

      def system_alert(message, severity: 'info')
        push_alert(type: 'system', severity: severity, message: message)
      end
    end

    def index
      render json: self.class.alerts
    end

    def create
      alert_params = params.permit(:type, :severity, :message)
      alert = self.class.push_alert(
        type: alert_params[:type] || 'custom',
        severity: alert_params[:severity] || 'info',
        message: alert_params[:message] || 'No message'
      )
      render json: alert, status: :created
    end

    def update
      return render json: { error: 'not_found' }, status: :not_found unless @alert

      self.class.mutex.synchronize do
        @alert[:read] = true if [true, 'true'].include?(params[:read])
      end
      render json: @alert
    end

    def destroy
      return render json: { error: 'not_found' }, status: :not_found unless @alert

      self.class.mutex.synchronize do
        self.class.alerts.delete(@alert)
      end
      head :no_content
    end

    private

    def find_alert
      id = params[:id].to_i
      self.class.mutex.synchronize do
        @alert = self.class.alerts.find { |a| a[:id] == id }
      end
    end
  end
end
