# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Loader do
  let(:strategy_record) { create(:strategy_record) }
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
  let(:file_path) { Rails.root.join('tmp', "#{slug}_strategy.rb").to_s }

  after do
    FileUtils.rm_f(file_path)
    Object.send(:remove_const, :MyTestStrategy) if Object.const_defined?(:MyTestStrategy) # rubocop:disable RSpec/RemoveConst
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
      allow(Strategies::Runtime).to receive(:register)
      described_class.load_version(version)
      expect(Strategies::Runtime).to have_received(:register).with('MyTestStrategy', anything, anything)
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

  context 'when file_path has a legacy workspace prefix but exists under Rails.root' do
    let(:slug) { 'legacy_path_test' }
    let(:content) { <<~RUBY }
      class MyTestStrategy < Strategies::Base
        def call(context) = :hold
      end
    RUBY
    let(:real_path) { Rails.root.join('strategies/legacy_test_strategy.rb').to_s }

    before do
      FileUtils.mkdir_p(File.dirname(real_path))
      File.write(real_path, content)
      version.update!(
        file_path: '/old/workspace/strategies/legacy_test_strategy.rb',
        checksum: Digest::SHA256.hexdigest(content)
      )
    end

    after do
      FileUtils.rm_f(real_path)
    end

    it 'resolves the file relative to Rails.root and loads successfully' do
      klass = described_class.load_version(version)
      expect(klass).to be < Strategies::Base
    end
  end
end
