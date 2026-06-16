# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::StreamConsumer do
  subject(:consumer) { described_class.new }

  describe '#start' do
    it 'does not start a thread when streams are disabled' do
      allow(OptionsBuying::Mode).to receive(:streams_enabled?).and_return(false)

      consumer.start

      expect(consumer.instance_variable_get(:@running)).to be(false)
      expect(consumer.instance_variable_get(:@thread)).to be_nil
    end
  end

  describe '#process_message!' do
    let(:fields) { { 'ltp' => '120.0', 'oi' => '4500', 'volume' => '9000', 'ts' => '1700000000' } }
    let(:tick) { { ltp: 120.0, oi: 4500, vol: 9000, ts: 1_700_000_000 } }

    before do
      allow(OptionsBuying::StateStore).to receive(:parse_stream_message).with(fields).and_return(tick)
      allow(OptionsBuying::StateStore).to receive(:xack)
      allow(OptionsBuying::BreakoutEvaluator).to receive(:evaluate_stream_tick!)
      allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY', sid: '13' }])
      allow(OptionsBuying::StateStore).to receive(:radar_strikes).with('NIFTY').and_return([{ security_id: 'opt1' }])
    end

    it 'evaluates the stream tick for the owning index and acks the message' do
      consumer.send(:process_message!, 'opt1', '1-0', fields)

      expect(OptionsBuying::BreakoutEvaluator).to have_received(:evaluate_stream_tick!).with(
        index_key: 'NIFTY', security_id: 'opt1', current_tick: tick
      )
      expect(OptionsBuying::StateStore).to have_received(:xack).with('opt1', '1-0')
    end

    it 'still acks (no redelivery loop) when the security maps to no index' do
      allow(OptionsBuying::StateStore).to receive(:radar_strikes).with('NIFTY').and_return([])

      consumer.send(:process_message!, 'unknown', '2-0', fields)

      expect(OptionsBuying::BreakoutEvaluator).not_to have_received(:evaluate_stream_tick!)
      expect(OptionsBuying::StateStore).to have_received(:xack).with('unknown', '2-0')
    end
  end

  describe '#read_batch' do
    it 'processes every message returned per monitored strike and counts them' do
      allow(OptionsBuying::StateStore).to receive_messages(
        monitored_strikes: ['opt1'],
        xreadgroup: { 'key1' => [['1-0', { 'ltp' => '1' }], ['2-0', { 'ltp' => '2' }]] }
      )
      allow(OptionsBuying::StateStore).to receive(:stream_key_for).with('opt1').and_return('key1')
      allow(consumer).to receive(:process_message!)

      expect(consumer.send(:read_batch)).to eq(2)
      expect(consumer).to have_received(:process_message!).twice
    end

    it 'returns zero when there are no monitored strikes' do
      allow(OptionsBuying::StateStore).to receive(:monitored_strikes).and_return([])
      expect(consumer.send(:read_batch)).to eq(0)
    end
  end
end
