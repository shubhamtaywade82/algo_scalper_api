# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Logs::TailReader do
  let(:dir) { Pathname.new(Dir.mktmpdir('tail-reader')) }
  let(:path) { dir.join('app.log') }

  after { FileUtils.remove_entry(dir) }

  it 'reports a missing file as a system warning instead of raising' do
    entries = described_class.new(dir.join('absent.log')).call

    expect(entries).to match([a_hash_including(id: 1, level: 'warn', source: 'System', message: /Log file not found/)])
  end

  it 'reports an unreadable path as a system error instead of raising' do
    entries = described_class.new(dir).call # a directory exists but cannot be read as a file

    expect(entries).to match([a_hash_including(id: 1, level: 'error', source: 'System', message: /Failed to read logs/)])
  end

  it 'numbers entries from 1 after dropping blank and noise lines' do
    path.write("[A] first\n\n  ↳ app/x.rb:1 query noise\n[B] second\n")

    entries = described_class.new(path).call

    expect(entries.pluck(:id, :source, :message)).to eq([[1, 'A', 'first'], [2, 'B', 'second']])
  end

  it 'lets a Ruby Logger prefix override the text-based level' do
    path.write("E, [2026-11-17T10:11:12.000000 #1] ERROR -- : all fine, no problem\nI, [2026-11-17T10:11:13.000000 #1]  INFO -- : an error was handled\n")

    entries = described_class.new(path).call

    expect(entries.pluck(:level, :timestamp)).to eq([%w[error 10:11:12], %w[info 10:11:13]])
  end

  it 'reads only the last MAX_LINES lines' do
    path.write((1..(described_class::MAX_LINES + 5)).map { |n| "[N] line #{n}" }.join("\n"))

    entries = described_class.new(path).call

    expect(entries.size).to be <= described_class::MAX_LINES
    expect(entries.last[:message]).to eq("line #{described_class::MAX_LINES + 5}")
  end
end
