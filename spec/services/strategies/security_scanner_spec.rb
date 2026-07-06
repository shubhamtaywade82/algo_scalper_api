# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::SecurityScanner do
  subject(:result) { described_class.new(content).scan }

  context 'with clean strategy code' do
    let(:content) { <<~RUBY }
      class MyStrategy < Strategies::Base
        def call(context)
          context.candles.call("5m").last[:close]
        end
      end
    RUBY

    it 'passes with no findings' do
      expect(result[:pass]).to be true
      expect(result[:blocked_count]).to be_zero
      expect(result[:warning_count]).to be_zero
    end
  end

  context 'with system/exec call' do
    let(:content) { 'system("ls")' }

    it 'blocks system execution' do
      expect(result[:pass]).to be false
      expect(result[:blocked_count]).to eq(1)
      expect(result[:blocked].first[:message]).to include('system')
    end
  end

  context 'with backtick execution' do
    let(:content) { '`ls -la`' }

    it 'blocks backtick execution' do
      expect(result[:pass]).to be false
      expect(result[:blocked_count]).to eq(1)
    end
  end

  context 'with File.write' do
    let(:content) { 'File.write("/tmp/x", "data")' }

    it 'blocks file writes' do
      expect(result[:pass]).to be false
      expect(result[:blocked_count]).to eq(1)
      expect(result[:blocked].first[:message]).to include('File.write')
    end
  end

  context 'with Thread.new' do
    let(:content) { 'Thread.new { sleep 1 }' }

    it 'blocks thread creation' do
      expect(result[:pass]).to be false
      expect(result[:blocked_count]).to eq(1)
      expect(result[:blocked].first[:message]).to include('Thread.new')
    end
  end

  context 'with platform constant references' do
    let(:content) { 'Orders::GatewayLive.new' }

    it 'blocks platform namespace access' do
      expect(result[:pass]).to be false
      expect(result[:blocked_count]).to eq(1)
      expect(result[:blocked].first[:message]).to include('Orders')
    end
  end

  context 'with sleep (warning)' do
    let(:content) { 'sleep 5' }

    it 'flags sleep as a warning' do
      expect(result[:pass]).to be true
      expect(result[:warning_count]).to eq(1)
      expect(result[:warnings].first[:message]).to include('sleep')
    end
  end

  context 'with syntax error' do
    let(:content) { 'class MyStrategy < Strategies::Base' }

    it 'returns blocker for syntax error' do
      expect(result[:pass]).to be false
      expect(result[:blocked_count]).to eq(1)
      expect(result[:blocked].first[:message]).to include('Syntax error')
    end
  end
end
