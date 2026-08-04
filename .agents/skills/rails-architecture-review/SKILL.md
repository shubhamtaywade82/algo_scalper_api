---
name: rails-architecture-review
description: >
  Performs structured architectural diagnosis of Ruby/Rails codebases. Evaluates code smell evidence,
  class coupling, fan-out, and complexity metrics to decide between introducing design patterns
  (with confidence scoring) or issuing NO_PATTERN.
---

# Rails Architecture Review Workflow

This skill outlines the step-by-step diagnostic workflow for evaluating Ruby/Rails software architecture.

---

## Architectural Review Execution Pipeline

```text
Inspect Repository Target
          │
          ▼
Run AST & Smell Analysis
(ruby_prism_ast_analyzer.rb & ruby_reek_smell_detector.rb)
          │
          ▼
Evaluate Git Co-Change & Dependencies
(rails_git_cochange.rb)
          │
          ▼
Identify Architectural Smells
(Fat Controller, God Model, Long Method, Switch Statements)
          │
          ▼
Evaluate Simpler Alternatives
(Can a simple private helper or PORO solve this?)
          │
          ├── YES ──► Issue NO_PATTERN
          │
          └── NO  ──► Evaluate Pattern Candidates
                            │
                            ▼
                    Calculate Confidence Score
                            │
                            ▼
                    Output Architecture Report
```

---

## Pattern Confidence Thresholds

- **< 0.50**: Reject pattern, return `NO_PATTERN`.
- **0.50 – 0.70**: Consider refactoring without formal pattern.
- **0.70 – 0.85**: Recommended pattern candidate.
- **> 0.85**: Strong candidate (high architectural justification).

---

## Required Output Format

Every architecture review report MUST follow this exact schema:

```markdown
### ARCHITECTURE REVIEW REPORT

**Component**: `app/services/orders/place_service.rb`

#### 1. Observed Problems
- Long Method (`call` method has 48 LOC)
- External Service Coupling (`DhanHQ::Client` called directly inside transaction)

#### 2. Measured Evidence
- **LOC**: 118
- **Branch Count**: 8
- **Class Fan-Out**: 12
- **Smells Detected**: `LongMethod`, `ExternalServiceCoupling`

#### 3. Recommended Architecture Changes
1. Extract `DhanGateway` adapter to encapsulate raw Dhan API calls.
2. Extract `OrderValidationPolicy` to remove validation logic from execution.

#### 4. Pattern Verdict
- **Adapter**: 0.91 Confidence (STRONG CANDIDATE)
- **Command**: 0.88 Confidence (STRONG CANDIDATE)
- **Factory**: NO_PATTERN (Object creation is straightforward constructor call)

#### 5. Trade-Offs & Complexity
- **Complexity Before**: 8/10
- **Complexity After**: 4/10
- **New Files**: `app/gateways/dhan_gateway.rb`

#### 6. Required Verification Specs
- `spec/gateways/dhan_gateway_spec.rb`
- `spec/services/orders/place_service_spec.rb`
```
