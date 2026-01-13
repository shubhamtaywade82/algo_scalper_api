# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'Smoke: Rake tasks load' do
  it 'loads all rake task files under lib/tasks' do
    rake_files = Rails.root.glob('lib/tasks/**/*.rake')
    expect(rake_files).not_to be_empty

    app = Rake::Application.new
    Rake.application = app

    # Ensure Rails environment task exists for dependencies
    app.define_task(Rake::Task, :environment)

    rake_files.each do |path|
      expect { app.add_import(path) }.not_to raise_error, "Failed to import rake file: #{path}"
    end

    expect { app.load_imports }.not_to raise_error
  ensure
    # Restore default rake application for other specs
    Rake.application = Rake::Application.new
  end
end
