# frozen_string_literal: true

module Strategies
  class SecurityScanner
    BLOCKER_METHODS = %w[
      system exec spawn fork
      eval instance_eval class_eval module_eval
      instance_exec class_exec module_exec
      send __send__ public_send
      method instance_variable_get instance_variable_set
      constantize
      require require_relative load
      popen syscall
      exit exit! abort at_exit trap
    ].freeze

    # Kernel functions dangerous as BARE calls whose names collide with
    # legitimate strategy-domain receivers: `open` is Candle#open (the OHLC
    # price accessor) all over plugin code, so it is only blocked as a bare
    # Kernel#open call (whose "|cmd" argument form executes commands).
    # IO/File/Dir/Pathname/Kernel receivers are blocked explicitly below.
    KERNEL_ONLY_BLOCKER_METHODS = %w[open].freeze

    BLOCKER_RECEIVER_CALLS = {
      "File" => %w[write open rename delete chmod chown mkdir rm cp mv symlink link unlink chdir binread],
      "FileUtils" => %w[cp mv rm mkdir rmdir rm_r rm_f rm_rf remove_entry remove_entry_secure
                        touch chmod chown ln ln_s cp_r],
      "Dir" => %w[open glob entries children mkdir chdir rmdir delete unlink home],
      "Pathname" => %w[new read write open binread binwrite delete unlink each_line foreach mkpath],
      "Thread" => %w[new start fork],
      "TCPSocket" => %w[new open],
      "UDPSocket" => %w[new open],
      "Socket" => %w[new open open_tcp open_udp],
      "IO" => %w[popen read write binread sysread open foreach readlines],
      "Open3" => %w[capture2 capture2e capture3 pipeline popen system],
      "Process" => %w[spawn exec fork kill detach setsid wait wait2 waitpid waitpid2 exit exit!],
      "ObjectSpace" => %w[each_object _id2ref memsize_of],
      "Signal" => %w[trap],
      "Kernel" => %w[system exec spawn fork abort open require load]
    }.freeze

    BLOCKER_CONST_PREFIXES = %w[
      Net:: HTTP:: Faraday:: Redis
    ].freeze

    BLOCKER_CONST_REFERENCES = %w[
      Orders Entries:: Live:: Redis Dhanhq Dhan
      Rails ENV Process Open3 IO Socket ObjectSpace
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
      when :CALL then check_receiver_call(node)
      when :CONST then check_const_ref(node)
      when :OPCALL then check_operator_call(node)
      when :BACKTICK, :XSTR then check_backtick(node)
      end

      node.children.each { |child| walk(child) }
    end

    def check_method_call(node)
      name = node.children.first.to_s
      line = node.first_lineno

      if BLOCKER_METHODS.include?(name) || KERNEL_ONLY_BLOCKER_METHODS.include?(name)
        return add_finding("blocker", "Uses #{name}", line)
      end

      if WARNING_METHODS.include?(name)
        add_finding("warning", "Uses #{name} (may block)", line)
      end
    end

    def check_receiver_call(node)
      method_name = node.children[1].to_s

      # Method-name blockers apply regardless of receiver: `obj.send(...)`,
      # `x.constantize`, `foo.instance_eval` must not slip through just
      # because they are attached to a receiver the lists don't know.
      if BLOCKER_METHODS.include?(method_name)
        return add_finding("blocker", "Uses #{method_name}", node.first_lineno)
      end

      receiver = resolve_receiver_name(node)
      return unless receiver

      if BLOCKER_RECEIVER_CALLS[receiver]&.include?(method_name)
        add_finding("blocker", "Uses #{receiver}.#{method_name}", node.first_lineno)
      end

      if BLOCKER_CONST_PREFIXES.any? { |p| receiver.start_with?(p) }
        add_finding("blocker", "Uses #{receiver}", node.first_lineno)
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

    def resolve_receiver_name(node)
      receiver = node.children[0]
      return nil unless receiver.is_a?(RubyVM::AbstractSyntaxTree::Node)

      case receiver.type
      when :CONST then receiver.children.first.to_s
      when :COLON2
        parts = []
        resolve_const(receiver, parts)
        parts.join("::")
      when :SELF then "self"
      end
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
