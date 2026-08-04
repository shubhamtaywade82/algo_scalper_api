---
name: rails-repo-intelligence
description: >
  Specification and workflow for Rails repository intelligence combining LSP (Ruby LSP + Rails add-on),
  Prism AST parser, Rails Semantic Index (RSI), Reek, RuboCop, Sorbet/Tapioca, and Git Co-Change
  to construct a context.for_task task context compiler.
---

# Rails Repository Intelligence & Context Compiler

This skill specifies how to synthesize multiple deterministic analysis tools to provide fast, targeted repository context to AI agents.

---

## The Intelligence Stack

```text
                  Task / User Request
                           │
                           ▼
               rails_context_compiler.rb
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
    AST Parser         LSP & Symbols       Git History
(Prism AST metrics)  (Ruby LSP/Zeitwerk)  (Git Co-Change)
        │                  │                  │
        └──────────────────┼──────────────────┘
                           ▼
                    Smell Detector
                   (Reek + RuboCop)
                           │
                           ▼
                     Pattern Advisor
                   (Pattern / NO_PATTERN)
                           │
                           ▼
                    TASK CONTEXT JSON
```

---

## Tooling Commands Reference

1. **AST Complexity Analysis**:
   ```bash
   ruby ~/.agents/skills/scripts/ruby_prism_ast_analyzer.rb <file_path>
   ```

2. **Smell Detection**:
   ```bash
   ruby ~/.agents/skills/scripts/ruby_reek_smell_detector.rb <file_or_dir_path>
   ```

3. **Git Co-Change "Files-to-Touch" Mapping**:
   ```bash
   ruby ~/.agents/skills/scripts/rails_git_cochange.rb <file_path>
   ```

4. **Pattern Advisory Evaluation**:
   ```bash
   ruby ~/.agents/skills/scripts/ruby_pattern_advisor.rb <file_or_dir_path>
   ```

5. **Full Task Context Compiler (`context.for_task`)**:
   ```bash
   ruby ~/.agents/skills/scripts/rails_context_compiler.rb <file_path>
   ```

---

## Integration Guidelines

When starting any refactoring, feature implementation, or architectural review task:
1. Run `rails_context_compiler.rb` on the target file.
2. Read the resulting JSON payload to get AST metrics, smells, associated spec files, co-change historical file mapping, and pattern advice.
3. Use this deterministic evidence to focus your code edits strictly on the minimal set of required files.
