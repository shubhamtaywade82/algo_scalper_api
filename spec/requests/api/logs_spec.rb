# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/logs' do # rubocop:disable RSpec/DescribeClass
  let(:log_path) { Rails.root.join('log', "#{Rails.env}.log") }
  let(:marker) { "LogSpec#{SecureRandom.hex(4)}" }

  # The endpoint tails the real environment log, so the spec appends uniquely marked lines to it
  # and reads them back from the last page.
  def append_log(*lines)
    File.open(log_path, 'a') { |file| lines.each { |line| file.puts(line) } }
  end

  def logs(**params)
    get '/api/logs', params: { page: 9999, per_page: 200 }.merge(params)
    response.parsed_body.fetch('logs')
  end

  def entry(logs, text)
    logs.find { |log| log['message'].to_s.include?(text) }
  end

  it 'splits a [Source] prefix off the message and defaults the level to info' do
    append_log("[#{marker}] hello #{marker}")

    log = entry(logs, "hello #{marker}")

    expect(log).to include('source' => marker, 'level' => 'info', 'message' => "hello #{marker}")
  end

  it 'detects error and warn levels from the text' do
    append_log("[#{marker}] something error happened", "[#{marker}] careful warn here")

    all = logs(source: marker)

    expect(entry(all, 'error happened')['level']).to eq('error')
    expect(entry(all, 'careful warn')['level']).to eq('warn')
  end

  it 'reads level, time and message from the Ruby Logger format' do
    append_log("W, [2026-11-17T10:11:12.123456 #4242]  WARN -- : #{marker} logger line")

    log = entry(logs, "#{marker} logger line")

    expect(log).to include('level' => 'warn', 'timestamp' => '10:11:12', 'source' => 'Rails')
  end

  it 'drops ANSI colour codes and database query noise' do
    append_log("\e[1m[#{marker}]\e[0m coloured #{marker}", "  ↳ app/models/x.rb:1 #{marker} NOISE", "User Load (1.2ms)  SELECT #{marker} NOISE")

    all = logs

    expect(entry(all, "coloured #{marker}")).to include('source' => marker, 'message' => "coloured #{marker}")
    expect(entry(all, "#{marker} NOISE")).to be_nil
  end

  it 'filters by level and by source substring' do
    append_log("[#{marker}] plain info", "[#{marker}] an error line")

    expect(logs(source: marker.downcase).pluck('source').uniq).to eq([marker])
    expect(logs(level: 'error', source: marker).pluck('message')).to eq(['an error line'])
  end

  it 'caps the page size and clamps the page into range' do
    get '/api/logs', params: { page: 9999, per_page: 100_000 }
    meta = response.parsed_body.fetch('meta')

    expect(meta['per_page']).to eq(200)
    expect(meta['page']).to eq(meta['pages'])
  end

  it 'uses the default page size when per_page is absent or not positive' do
    get '/api/logs'
    expect(response.parsed_body.dig('meta', 'per_page')).to eq(50)

    get '/api/logs', params: { per_page: 0 }
    expect(response.parsed_body.dig('meta', 'per_page')).to eq(50)
  end
end
