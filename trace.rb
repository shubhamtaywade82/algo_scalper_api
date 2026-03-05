require_relative 'config/environment'
TracePoint.new(:call) do |tp|
  if tp.path.include?('app/services/signal/engine.rb') || tp.path.include?('market_regime_detector.rb')
    puts "#{tp.defined_class}##{tp.method_id} at #{tp.path}:#{tp.lineno}"
  end
end.enable do
  RSpec::Core::Runner.run(['spec/services/signal/engine_spec.rb:73'])
end
