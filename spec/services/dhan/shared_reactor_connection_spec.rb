# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::SharedReactorConnection do
  let(:handlers) { {} }
  let(:socket) { instance_double(Faye::WebSocket::Client, close: true) }
  let(:connection) do
    DhanHQ::WS::Connection.new(url: 'wss://feed.example', mode: :quote, bus: nil, state: nil)
  end

  before do
    allow(socket).to receive(:on) { |event, &blk| handlers[event] = blk }
    allow(Faye::WebSocket::Client).to receive(:new).and_return(socket)
    described_class.ensure_reactor!
  end

  after do
    connection.instance_variable_set(:@stop, true)
    connection.instance_variable_set(:@stopping, true)
    handlers[:close]&.call(Struct.new(:code, :reason).new(1000, 'stop'))
    connection.instance_variable_get(:@thr)&.join(2)
    EM.stop if EM.reactor_running?
  end

  it 'opens one socket per session instead of spinning when the reactor already runs' do
    connection.start
    sleep 0.5

    expect(Faye::WebSocket::Client).to have_received(:new).once
  end
end
