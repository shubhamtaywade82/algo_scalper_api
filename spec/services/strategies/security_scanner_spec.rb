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

  context 'with IO.popen (RCE vector missed before the 2026-09 expansion)' do
    let(:content) { 'IO.popen("ls") { |io| io.read }' }

    it 'blocks IO.popen' do
      expect(result[:pass]).to be false
      expect(result[:blocked].pluck(:message)).to include(satisfy { |m| m.include?('popen') })
    end
  end

  context 'with Process.spawn' do
    let(:content) { 'Process.spawn("touch /tmp/x")' }

    it 'blocks Process.spawn' do
      expect(result[:pass]).to be false
    end
  end

  context 'with send dispatch' do
    let(:content) { 'series.send(:system, "ls")' }

    it 'blocks send regardless of receiver' do
      expect(result[:pass]).to be false
      expect(result[:blocked].pluck(:message)).to include(satisfy { |m| m.include?('send') })
    end
  end

  context 'with constantize' do
    let(:content) { '"Orders::Gateway".constantize' }

    it 'blocks constantize' do
      expect(result[:pass]).to be false
    end
  end

  context 'with require' do
    let(:content) { 'require "open3"' }

    it 'blocks require' do
      expect(result[:pass]).to be false
    end
  end

  context 'with Rails constant access' do
    let(:content) { 'Rails.logger.info("x")' }

    it 'blocks Rails references' do
      expect(result[:pass]).to be false
    end
  end

  context 'with ENV access' do
    let(:content) { 'ENV.fetch("DHAN_ACCESS_TOKEN", nil)' }

    it 'blocks ENV references' do
      expect(result[:pass]).to be false
    end
  end
end
