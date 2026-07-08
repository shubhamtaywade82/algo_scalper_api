# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Loader do
  let(:strategy_record) { create(:strategy_record) }
  let(:file_path) { Rails.root.join('tmp', "#{slug}_strategy.rb").to_s }

  after do
    FileUtils.rm_f(file_path)
    Object.send(:remove_const, :MyTestStrategy) if Object.const_defined?(:MyTestStrategy)
  end

  let(:version) do
    Strategies::Version.create!(
      strategy_record: strategy_record,
      version: 1,
      file_path: file_path,
      checksum: Digest::SHA256.hexdigest(content),
      manifest: { 'class_name' => 'MyTestStrategy', 'params' => {} },
      deployed_at: Time.current
    )
  end

  context 'when checksum matches' do
    let(:slug) { 'my_test' }
    let(:content) { <<~RUBY }
      class MyTestStrategy < Strategies::Base
        def call(context) = :hold
      end
    RUBY

    before { File.write(file_path, content) }

    it 'loads the strategy class' do
      klass = described_class.load_version(version)
      expect(klass).to be < Strategies::Base
      expect(klass.new.call(nil)).to eq(:hold)
    end

    it 'registers in Runtime' do
      expect(Strategies::Runtime).to receive(:register).with('MyTestStrategy', anything, anything)
      described_class.load_version(version)
    end
  end

  context 'when checksum mismatches' do
    let(:slug) { 'my_test' }
    let(:content) { 'class MyTestStrategy < Strategies::Base; end' }

    before do
      File.write(file_path, content)
      version.update!(checksum: 'badchecksum')
    end

    it 'raises ChecksumMismatch' do
      expect { described_class.load_version(version) }
        .to raise_error(Strategies::Loader::ChecksumMismatch)
    end
  end

  context 'when class is not defined in file' do
    let(:slug) { 'missing_class' }
    let(:content) { '# just a comment' }

    before do
      File.write(file_path, content)
      version.update!(checksum: Digest::SHA256.hexdigest(content))
    end

    it 'raises ClassNotFound' do
      expect { described_class.load_version(version) }
        .to raise_error(Strategies::Loader::ClassNotFound)
    end
  end
end
