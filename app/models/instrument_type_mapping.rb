# frozen_string_literal: true

module InstrumentTypeMapping
  PARENT_TO_CHILDREN = {
    "INDEX" => %w[FUTIDX OPTIDX],
    "EQUITY" => %w[FUTSTK OPTSTK],
    "FUTCOM" => %w[OPTFUT],
    "FUTCUR" => %w[OPTCUR]
  }.freeze

  CHILD_TO_PARENT =
    PARENT_TO_CHILDREN.flat_map { |parent, kids| kids.map { |kid| [ kid, parent ] } }
                      .to_h
                      .freeze

  module_function

  def underlying_for(code)
    return nil if code.blank?

    CHILD_TO_PARENT[code] || code
  end

  def derivative_codes_for(parent_code)
    PARENT_TO_CHILDREN[parent_code] || []
  end

  def all_parents
    PARENT_TO_CHILDREN.keys
  end

  def all_children
    CHILD_TO_PARENT.keys
  end
end
