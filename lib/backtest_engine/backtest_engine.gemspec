Gem::Specification.new do |spec|
  spec.name          = "backtest_engine"
  spec.version       = "0.1.0"
  spec.summary       = "Index‑driven options backtesting engine for DhanHQ data"
  spec.description   = "Modular NIFTY options backtester driven by index structure, with pluggable strategies and realistic execution."
  spec.authors       = ["nemesis"]
  spec.email         = ["dev@example.com"]

  spec.files         = Dir.glob("lib/**/*") + ["README.md", "backtest_engine-plan.md"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.1"

  spec.add_dependency "DhanHQ"

  spec.add_development_dependency "rspec"
end

