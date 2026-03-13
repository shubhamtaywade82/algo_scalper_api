# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tempfile'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'options:calibrate_from_csv rake task' do
  let(:rake) { Rake::Application.new }
  let(:task_name) { 'options:calibrate_from_csv' }
  let(:batch_task_name) { 'options:calibrate_batch' }
  let(:csv_content) do
    <<~CSV
      symbol,expiry,from,to,ce_entry,ce_exit,ce_max_gain_pct,ce_max_loss_pct,ce_oc_pct,ce_retrace,ce_oi_chg,ce_spot_chg,ce_corr_slope,ce_strike,pe_entry,pe_exit,pe_max_gain_pct,pe_max_loss_pct,pe_oc_pct,pe_retrace,pe_oi_chg,pe_spot_chg,pe_corr_slope,pe_strike,ce_morning_oc,ce_midday_oc,ce_afternoon_oc,pe_morning_oc,pe_midday_oc,pe_afternoon_oc
      SENSEX,2026-03-05,2026-02-27,2026-03-05,100,115,22,-14,15,-28,10,1.2,2.4,84000,105,95,18,-12,-9,-25,8,1.2,2.1,84000,4.2,-1.0,2.1,3.8,-1.7,1.5
      SENSEX,2026-03-12,2026-03-06,2026-03-12,110,108,16,-11,-2,-21,6,-0.7,1.9,84100,120,132,24,-13,10,-30,9,-0.7,2.5,84100,2.9,-0.8,1.4,3.1,-2.2,1.9
    CSV
  end

  before do
    Rake.application = rake
    rake.add_import(Rails.root.join('lib/tasks/options_calibration.rake').to_s)
    rake.load_imports
  end

  after do
    Rake.application = Rake::Application.new
  end

  it 'prints profile recommendations and yaml patch' do
    file = Tempfile.new(['options_intraday', '.csv'])
    file.write(csv_content)
    file.rewind

    output = capture_stdout do
      rake[task_name].reenable
      rake[task_name].invoke(file.path, 'SENSEX')
    end

    expect(output).to include('Objective Score Summary')
    expect(output).to include('Recommended Profiles')
    expect(output).to include('Suggested algo.yml patch')
    expect(output).to include('Confidence & Warnings')
  ensure
    file.close
    file.unlink
  end

  it 'supports batch mode and prints median patch suggestion' do
    f1 = Tempfile.new(['options_intraday_a', '.csv'])
    f2 = Tempfile.new(['options_intraday_b', '.csv'])
    [f1, f2].each do |f|
      f.write(csv_content)
      f.rewind
    end

    glob = File.join(File.dirname(f1.path), 'options_intraday_*.csv')
    output = capture_stdout do
      rake[batch_task_name].reenable
      rake[batch_task_name].invoke(glob, 'SENSEX')
    end

    expect(output).to include('Batch Calibration Summary')
    expect(output).to include('Median balanced patch suggestion')
  ensure
    [f1, f2].each do |f|
      f.close
      f.unlink
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
# rubocop:enable RSpec/DescribeClass
