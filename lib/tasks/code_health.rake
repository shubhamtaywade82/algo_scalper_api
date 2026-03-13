namespace :code_health do
  desc "Run debride dead code analysis"
  task :debride do
    sh "bundle exec debride app lib"
  end

  desc "Run Rails Best Practices (requires gem in bundle)"
  task :rails_best_practices do
    sh "bundle exec rails_best_practices ."
  end

  desc "Run all code health checks (static dead code only for now)"
  task all: %i[debride] # add :rails_best_practices once gem is bundled
end

