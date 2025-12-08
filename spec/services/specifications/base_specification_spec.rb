# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Specifications::BaseSpecification do
  let(:spec_class) do
    Class.new(Specifications::BaseSpecification) do
      def initialize(value)
        @value = value
      end

      def satisfied?(context)
        @value == true
      end

      def failure_reason(context)
        satisfied?(context) ? nil : 'Value is not true'
      end
    end
  end

  let(:true_spec) { spec_class.new(true) }
  let(:false_spec) { spec_class.new(false) }

  describe '#satisfied?' do
    it 'must be implemented by subclass' do
      abstract_spec = Specifications::BaseSpecification.new

      expect do
        abstract_spec.satisfied?(nil)
      end.to raise_error(NotImplementedError)
    end

    it 'returns true when condition is met' do
      expect(true_spec.satisfied?(nil)).to be true
    end

    it 'returns false when condition is not met' do
      expect(false_spec.satisfied?(nil)).to be false
    end
  end

  describe '#failure_reason' do
    it 'returns nil when satisfied' do
      expect(true_spec.failure_reason(nil)).to be_nil
    end

    it 'returns failure reason when not satisfied' do
      expect(false_spec.failure_reason(nil)).to eq('Value is not true')
    end
  end

  describe '#and' do
    let(:other_spec) { spec_class.new(true) }

    it 'creates AndSpecification' do
      combined = true_spec.and(other_spec)

      expect(combined).to be_a(Specifications::AndSpecification)
    end

    it 'returns true when both specifications satisfied' do
      combined = true_spec.and(other_spec)

      expect(combined.satisfied?(nil)).to be true
    end

    it 'returns false when one specification not satisfied' do
      combined = false_spec.and(other_spec)

      expect(combined.satisfied?(nil)).to be false
      expect(combined.failure_reason(nil)).to eq('Value is not true')
    end
  end

  describe '#or' do
    let(:other_spec) { spec_class.new(false) }

    it 'creates OrSpecification' do
      combined = true_spec.or(other_spec)

      expect(combined).to be_a(Specifications::OrSpecification)
    end

    it 'returns true when either specification satisfied' do
      combined = true_spec.or(other_spec)

      expect(combined.satisfied?(nil)).to be true
    end

    it 'returns false when both specifications not satisfied' do
      combined = false_spec.or(other_spec)

      expect(combined.satisfied?(nil)).to be false
    end
  end

  describe '#not' do
    it 'creates NotSpecification' do
      negated = true_spec.not

      expect(negated).to be_a(Specifications::NotSpecification)
    end

    it 'negates the specification' do
      negated = true_spec.not

      expect(negated.satisfied?(nil)).to be false
    end

    it 'negates false to true' do
      negated = false_spec.not

      expect(negated.satisfied?(nil)).to be true
    end
  end

  describe 'AndSpecification' do
    let(:spec1) { spec_class.new(true) }
    let(:spec2) { spec_class.new(true) }
    let(:spec3) { spec_class.new(false) }
    let(:and_spec) { Specifications::AndSpecification.new(spec1, spec2) }

    it 'returns true when both satisfied' do
      expect(and_spec.satisfied?(nil)).to be true
    end

    it 'returns false when first not satisfied' do
      and_spec_false = Specifications::AndSpecification.new(spec3, spec2)

      expect(and_spec_false.satisfied?(nil)).to be false
      expect(and_spec_false.failure_reason(nil)).to eq('Value is not true')
    end

    it 'returns false when second not satisfied' do
      and_spec_false = Specifications::AndSpecification.new(spec1, spec3)

      expect(and_spec_false.satisfied?(nil)).to be false
      expect(and_spec_false.failure_reason(nil)).to eq('Value is not true')
    end
  end

  describe 'OrSpecification' do
    let(:spec1) { spec_class.new(true) }
    let(:spec2) { spec_class.new(false) }
    let(:spec3) { spec_class.new(false) }
    let(:or_spec) { Specifications::OrSpecification.new(spec1, spec2) }

    it 'returns true when first satisfied' do
      expect(or_spec.satisfied?(nil)).to be true
    end

    it 'returns true when second satisfied' do
      or_spec2 = Specifications::OrSpecification.new(spec2, spec1)

      expect(or_spec2.satisfied?(nil)).to be true
    end

    it 'returns false when both not satisfied' do
      or_spec_false = Specifications::OrSpecification.new(spec2, spec3)

      expect(or_spec_false.satisfied?(nil)).to be false
    end
  end

  describe 'NotSpecification' do
    let(:spec) { spec_class.new(true) }
    let(:not_spec) { Specifications::NotSpecification.new(spec) }

    it 'negates true to false' do
      expect(not_spec.satisfied?(nil)).to be false
    end

    it 'negates false to true' do
      false_spec = spec_class.new(false)
      not_spec_false = Specifications::NotSpecification.new(false_spec)

      expect(not_spec_false.satisfied?(nil)).to be true
    end
  end
end
