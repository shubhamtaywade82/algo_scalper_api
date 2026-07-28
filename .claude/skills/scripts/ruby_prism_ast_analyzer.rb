#!/usr/bin/env ruby
# frozen_string_literal: true

require 'prism'
require 'json'

class PrismAstAnalyzer
  attr_reader :file_path, :result

  def initialize(file_path)
    @file_path = file_path
    @result = {
      file: file_path,
      loc: 0,
      classes: [],
      modules: [],
      methods: [],
      branches: 0,
      constant_references: [],
      instance_variables: [],
      metrics: {
        method_count: 0,
        avg_method_loc: 0,
        max_method_loc: 0,
        branch_count: 0,
        class_fan_out: 0,
        conditional_density: 0.0
      }
    }
  end

  def analyze
    return result unless File.exist?(file_path)

    content = File.read(file_path)
    result[:loc] = content.lines.count

    parsed = Prism.parse(content)
    return result unless parsed.success?

    visit_node(parsed.value)

    calculate_metrics
    result
  end

  private

  def visit_node(node)
    return if node.nil?

    case node
    when Prism::ClassNode
      name = node.name.to_s
      result[:classes] << name
    when Prism::ModuleNode
      name = node.name.to_s
      result[:modules] << name
    when Prism::DefNode
      name = node.name.to_s
      start_line = node.location.start_line
      end_line = node.location.end_line
      loc = end_line - start_line + 1
      result[:methods] << { name: name, loc: loc, start_line: start_line, end_line: end_line }
    when Prism::IfNode, Prism::UnlessNode, Prism::CaseNode, Prism::WhenNode
      result[:branches] += 1
    when Prism::AndNode, Prism::OrNode
      result[:branches] += 1
    when Prism::ConstantReadNode, Prism::ConstantPathNode
      result[:constant_references] << node.slice.to_s
    when Prism::InstanceVariableReadNode, Prism::InstanceVariableWriteNode, Prism::InstanceVariableTargetNode
      var_name = node.name.to_s
      result[:instance_variables] << var_name unless result[:instance_variables].include?(var_name)
    end

    node.compact_child_nodes.each { |child| visit_node(child) }
  end

  def calculate_metrics
    methods = result[:methods]
    result[:metrics][:method_count] = methods.size

    if methods.any?
      locs = methods.map { |m| m[:loc] }
      result[:metrics][:avg_method_loc] = (locs.sum.to_f / locs.size).round(1)
      result[:metrics][:max_method_loc] = locs.max
    end

    result[:metrics][:branch_count] = result[:branches]
    result[:constant_references].uniq!
    result[:metrics][:class_fan_out] = result[:constant_references].size

    if result[:loc] > 0
      result[:metrics][:conditional_density] = (result[:branches].to_f / result[:loc]).round(3)
    end
  end
end

if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: ruby_prism_ast_analyzer.rb <file_path>"
    exit 1
  end

  file_path = ARGV[0]
  analyzer = PrismAstAnalyzer.new(file_path)
  puts JSON.pretty_generate(analyzer.analyze)
end
