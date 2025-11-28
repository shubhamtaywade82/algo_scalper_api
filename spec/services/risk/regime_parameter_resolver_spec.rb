# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::RegimeParameterResolver do
  let(:regime_result) { { regime: :high, vix_value: 22.0, regime_name: 'High Volatility' } }
  let(:condition_result) { { condition: :bullish, trend_score: 16.0, adx_value: 25.0, condition_name: 'Bullish' } }

  before do
    allow(Risk::VolatilityRegimeService).to receive(:call).and_return(regime_result)
    allow(Risk::MarketConditionService).to receive(:call).and_return(condition_result)
  end

  describe '.call' do
    context 'when regime and condition are provided' do
      it 'resolves parameters for NIFTY high volatility bullish' do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                }
              }
            }
          }
        })

        result = described_class.call(index_key: 'NIFTY', regime: :high, condition: :bullish)
        expect(result[:index_key]).to eq('NIFTY')
        expect(result[:regime]).to eq(:high)
        expect(result[:condition]).to eq(:bullish)
        expect(result[:parameters][:sl_pct_range]).to eq([8, 12])
        expect(result[:parameters][:tp_pct_range]).to eq([18, 30])
      end
    end

    context 'when auto-detecting regime and condition' do
      it 'calls VolatilityRegimeService and MarketConditionService' do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                }
              }
            }
          }
        })

        expect(Risk::VolatilityRegimeService).to receive(:call).and_return(regime_result)
        expect(Risk::MarketConditionService).to receive(:call).with(index_key: 'NIFTY').and_return(condition_result)

        result = described_class.call(index_key: 'NIFTY')
        expect(result[:regime]).to eq(:high)
        expect(result[:condition]).to eq(:bullish)
      end
    end

    context 'with different volatility regimes' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  },
                  medium_volatility: {
                    bullish: {
                      sl_pct_range: [6, 8],
                      tp_pct_range: [10, 18],
                      trail_pct_range: [5, 7],
                      timeout_minutes: [8, 12]
                    }
                  },
                  low_volatility: {
                    bullish: {
                      sl_pct_range: [3, 5],
                      tp_pct_range: [4, 7],
                      trail_pct_range: [2, 3],
                      timeout_minutes: [3, 8]
                    }
                  }
                }
              }
            }
          }
        })
      end

      it 'resolves high volatility parameters' do
        result = described_class.call(index_key: 'NIFTY', regime: :high, condition: :bullish)
        expect(result[:parameters][:sl_pct_range]).to eq([8, 12])
        expect(result[:parameters][:tp_pct_range]).to eq([18, 30])
      end

      it 'resolves medium volatility parameters' do
        result = described_class.call(index_key: 'NIFTY', regime: :medium, condition: :bullish)
        expect(result[:parameters][:sl_pct_range]).to eq([6, 8])
        expect(result[:parameters][:tp_pct_range]).to eq([10, 18])
      end

      it 'resolves low volatility parameters' do
        result = described_class.call(index_key: 'NIFTY', regime: :low, condition: :bullish)
        expect(result[:parameters][:sl_pct_range]).to eq([3, 5])
        expect(result[:parameters][:tp_pct_range]).to eq([4, 7])
      end
    end

    context 'with different market conditions' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    },
                    bearish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [15, 28],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                }
              }
            }
          }
        })
      end

      it 'resolves bullish parameters' do
        result = described_class.call(index_key: 'NIFTY', regime: :high, condition: :bullish)
        expect(result[:parameters][:tp_pct_range]).to eq([18, 30])
      end

      it 'resolves bearish parameters' do
        result = described_class.call(index_key: 'NIFTY', regime: :high, condition: :bearish)
        expect(result[:parameters][:tp_pct_range]).to eq([15, 28])
      end
    end

    context 'with different indices' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                },
                BANKNIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [10, 15],
                      tp_pct_range: [25, 40],
                      trail_pct_range: [10, 15],
                      timeout_minutes: [10, 20]
                    }
                  }
                },
                SENSEX: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 13],
                      tp_pct_range: [18, 28],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                }
              }
            }
          }
        })
      end

      it 'resolves NIFTY parameters' do
        result = described_class.call(index_key: 'NIFTY', regime: :high, condition: :bullish)
        expect(result[:parameters][:sl_pct_range]).to eq([8, 12])
      end

      it 'resolves BANKNIFTY parameters' do
        result = described_class.call(index_key: 'BANKNIFTY', regime: :high, condition: :bullish)
        expect(result[:parameters][:sl_pct_range]).to eq([10, 15])
      end

      it 'resolves SENSEX parameters' do
        result = described_class.call(index_key: 'SENSEX', regime: :high, condition: :bullish)
        expect(result[:parameters][:sl_pct_range]).to eq([8, 13])
      end
    end

    context 'when regime-based params are disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: false
            },
            sl_pct: 30,
            tp_pct: 60
          }
        })
      end

      it 'falls back to default parameters' do
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:parameters][:sl_pct_range]).to eq([30, 30])
        expect(result[:parameters][:tp_pct_range]).to eq([60, 60])
      end
    end

    context 'when parameters not found for index' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                }
              }
            },
            sl_pct: 30,
            tp_pct: 60
          }
        })
      end

      it 'falls back to default parameters' do
        result = described_class.call(index_key: 'UNKNOWN')
        expect(result[:parameters][:sl_pct_range]).to eq([30, 30])
      end
    end

    describe '#sl_pct' do
      it 'returns midpoint of sl_pct_range' do
        resolver = described_class.new(index_key: 'NIFTY', regime: :high, condition: :bullish)
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                }
              }
            }
          }
        })
        resolver.call
        expect(resolver.sl_pct).to eq(10.0)
      end
    end

    describe '#tp_pct' do
      it 'returns midpoint of tp_pct_range' do
        resolver = described_class.new(index_key: 'NIFTY', regime: :high, condition: :bullish)
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                }
              }
            }
          }
        })
        resolver.call
        expect(resolver.tp_pct).to eq(24.0)
      end
    end

    describe '#sl_pct_random' do
      it 'returns random value within range' do
        resolver = described_class.new(index_key: 'NIFTY', regime: :high, condition: :bullish)
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk: {
            volatility_regimes: {
              enabled: true,
              parameters: {
                NIFTY: {
                  high_volatility: {
                    bullish: {
                      sl_pct_range: [8, 12],
                      tp_pct_range: [18, 30],
                      trail_pct_range: [7, 12],
                      timeout_minutes: [10, 18]
                    }
                  }
                }
              }
            }
          }
        })
        resolver.call
        random_value = resolver.sl_pct_random
        expect(random_value).to be_between(8.0, 12.0)
      end
    end

    context 'error handling' do
      it 'handles exceptions gracefully' do
        allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'Config error')
        result = described_class.call(index_key: 'NIFTY')
        expect(result[:parameters]).to be_a(Hash)
        expect(result[:parameters][:sl_pct_range]).to be_a(Array)
      end
    end
  end
end
