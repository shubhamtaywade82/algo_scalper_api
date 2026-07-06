# frozen_string_literal: true

module Strategies
  class SecurityScanner
    BLOCKER_METHODS = %w[
      system exec spawn fork
      eval instance_eval class_eval module_eval
    ].freeze

    BLOCKER_CALL_PATTERNS = [
      /\AFile\.(write|open|rename|delete|chmod|chown|mkdir|rm|cp|mv)\z/,
      /\AFileUtils\./,
      /\ANet::HTTP\z/,
      /\A(TCPSocket|UDPSocket|Socket)\z/,
      /\AThread\.(new|start|fork)\z/,
    ].freeze

    BLOCKER_CONST_REFERENCES = %w[
      Orders Entries:: Live:: Redis Dhanhq Dhan
    ].freeze

    WARNING_METHODS = %w[sleep].freeze

    WARNING_CONST_REFERENCES = %w[
      Time Date DateTime
    ].freeze

    def initialize(content)
      @content = content
      @findings = []
    end

    def scan
      ast = RubyVM::AbstractSyntaxTree.parse(@content)
      walk(ast)
      {
        blocked: @findings.select { |f| f[:severity] == "blocker" },
        warnings: @findings.select { |f| f[:severity] == "warning" },
        blocked_count: @findings.count { |f| f[:severity] == "blocker" },
        warning_count: @findings.count { |f| f[:severity] == "warning" },
        pass: @findings.none? { |f| f[:severity] == "blocker" }
      }
    rescue SyntaxError => e
      { blocked: [{ severity: "blocker", message: "Syntax error: #{e.message}", line: 0 }],
        warnings: [], blocked_count: 1, warning_count: 0, pass: false }
    end

    private

    def walk(node)
      return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)

      case node.type
      when :FCALL, :VCALL then check_method_call(node)
      when :CONST then check_const_ref(node)
      when :OPCALL then check_operator_call(node)
      when :BACKTICK then check_backtick(node)
      end

      node.children.each { |child| walk(child) }
    end

    def check_method_call(node)
      name = node.children.first.to_s
      line = node.first_lineno

      if BLOCKER_METHODS.include?(name)
        return add_finding("blocker", "Uses #{name}", line)
      end

      if WARNING_METHODS.include?(name)
        return add_finding("warning", "Uses #{name} (may block)", line)
      end

      BLOCKER_CALL_PATTERNS.each do |pattern|
        if name.match?(pattern)
          return add_finding("blocker", "Uses #{name}", line)
        end
      end
    end

    def check_const_ref(node)
      parts = []
      resolve_const(node, parts)
      name = parts.join("::")
      return if name.empty?

      if BLOCKER_CONST_REFERENCES.any? { |ref| name.start_with?(ref) }
        add_finding("blocker", "Forbidden constant #{name}", node.first_lineno)
      elsif WARNING_CONST_REFERENCES.any? { |ref| name.start_with?(ref) }
        add_finding("warning", "References #{name} (use context.clock)", node.first_lineno)
      end
    end

    def check_operator_call(node)
      return unless node.children[1] == :`

      add_finding("blocker", "Uses backtick execution", node.first_lineno)
    end

    def check_backtick(node)
      add_finding("blocker", "Uses backtick execution", node.first_lineno)
    end

    def resolve_const(node, parts)
      case node.type
      when :CONST
        parts << node.children.first.to_s
      when :COLON2
        resolve_const(node.children[0], parts)
        parts << node.children[1].to_s if node.children[1].is_a?(Symbol)
      when :COLON3
        parts << node.children[0].to_s
      end
    end

    def add_finding(severity, message, line)
      @findings << { severity: severity, message: message, line: line }
    end
  end
end
