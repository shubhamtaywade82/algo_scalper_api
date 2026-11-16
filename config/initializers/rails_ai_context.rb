# frozen_string_literal: true

if defined?(RailsAiContext) && RailsAiContext.respond_to?(:configure)
  RailsAiContext.configure do |config|
    # ── AI Tools ──────────────────────────────────────────────────────
    # Which AI tools to generate context files for (selected during install)
    # Run `rails generate rails_ai_context:install` to change selection
    config.ai_tools = %i[claude cursor copilot opencode codex]

    # Tool invocation mode:
    #   :mcp - MCP primary + CLI fallback (default, requires `rails ai:serve`)
    #   :cli - CLI only (no MCP server needed, uses `rails 'ai:tool[NAME]'`)
    config.tool_mode = :mcp   # MCP primary + CLI fallback
    config.context_files = false  # MCP only: no context files are written

    # ── Introspection ─────────────────────────────────────────────────
    # Introspector preset:
    #   :full     - all 40 introspectors (default)
    #   :standard - 17 core introspectors (schema, models, routes, jobs, gems,
    #               conventions, controllers, tests, migrations, stimulus,
    #               view_templates, config, components, turbo, auth,
    #               performance, i18n)
    # config.preset = :full

    # Context mode: :compact (default, ≤150 lines) or :full (dumps everything)
    # config.context_mode = :compact

    # Max lines for CLAUDE.md in compact mode
    # config.claude_max_lines = 150

    # Whether to generate root files (CLAUDE.md, AGENTS.md, etc.)
    # Set false to only generate split rules (.claude/rules/, .cursor/rules/, etc.)
    # config.generate_root_files = true

    # Anti-Hallucination Protocol: 6-rule verification section embedded in every
    # generated context file. Forces AI to verify facts before writing code.
    # Default: true. Set false to skip the protocol entirely.
    # config.anti_hallucination_rules = true

    # Every tool answer ends with one line asking the agent to offer you a
    # GitHub issue when rails-ai-context answered wrong. Set false to leave it out.
    # config.report_issue_line = true

    # ── Models & Filtering ────────────────────────────────────────────
    # Models to exclude from introspection
    # config.excluded_models += %w[AdminUser InternalThing]

    # Framework association names hidden from model output
    # (ActiveStorage, ActionText, ActionMailbox, Noticed associations are excluded by default)
    # config.excluded_association_names += %w[my_custom_framework_assoc]

    # Controllers to exclude from listings
    # config.excluded_controllers += %w[Admin::BaseController]

    # Route prefixes to hide with app_only filter
    # config.excluded_route_prefixes += %w[sidekiq/]

    # ── MCP Server ────────────────────────────────────────────────────
    # Cache TTL in seconds for introspection data
    # config.cache_ttl = 60

    # Max characters for any single tool response (safety net)
    # config.max_tool_response_chars = 200_000

    # Live reload: auto-invalidate MCP tool caches on file changes
    #   :auto - enable if `listen` gem is available (default)
    #   true  - enable, raise if `listen` gem is missing
    #   false - disable entirely
    # config.live_reload = :auto

    # Auto-mount HTTP MCP endpoint (for HTTP transport)
    # config.auto_mount = false
    # config.http_path = "/mcp"
    # config.http_port = 6029

    # ── File Size Limits ──────────────────────────────────────────────
    # Increase for larger projects
    # config.max_file_size = 5_000_000         # Per-file read (5MB)
    # config.max_test_file_size = 1_000_000    # Test file read (1MB)
    # config.max_schema_file_size = 10_000_000 # schema.rb parse (10MB)
    # config.max_view_total_size = 10_000_000  # Doctor view-size threshold (10MB)
    # config.max_view_file_size = 1_000_000    # Accepted and stored; no check reads it (1MB)
    # config.max_search_results = 200          # Max search results per call
    # config.max_validate_files = 50           # Max files per validate call

    # ── Extensibility ─────────────────────────────────────────────────
    # Register additional MCP tool classes alongside the 35 built-in tools
    # config.custom_tools = ["MyApp::CustomTool"]  # class name as string - resolved after boot

    # Exclude specific built-in tools by name
    # config.skip_tools = %w[rails_security_scan]

    # ── Security ──────────────────────────────────────────────────────
    # Paths excluded from code search
    # config.excluded_paths += %w[vendor/cache]

    # File patterns blocked from search and read tools
    # config.sensitive_patterns += %w[config/secrets.yml]

    # ── Database Query Tool (rails_query) ─────────────────────────────
    # Per-query statement timeout in seconds. Default: 5.
    # config.query_timeout = 5

    # Hard cap on rows returned by a single query (1..1000).
    # Prevents accidentally pulling a million-row table into the
    # AI's context. Default: 100.
    # config.query_row_limit = 100

    # Column names a query may not touch: one that names any of them
    # is rejected before it runs, and a returned column of that name
    # comes back [FILTERED]. The defaults already list password_digest,
    # encrypted_password, api_key, access_token and the like, and a
    # built-in list is checked on top of them.
    # config.query_redacted_columns += %w[my_app_specific_secret]

    # rails_query is DISABLED in production by default. Setting
    # this to true is rarely correct - only do so if you have
    # audit logging + access controls around your AI client.
    # config.allow_query_in_production = false

    # ── Log Reading (rails_read_logs) ─────────────────────────────────
    # Default tail length when reading a log file. Larger values
    # surface more context but cost more AI tokens per call.
    # config.log_lines = 50

    # ── Hydration ─────────────────────────────────────────────────────
    # When enabled, MCP tool responses include schema hints telling
    # the AI which related tools to call next. Helps agents
    # traverse the introspection graph efficiently. Default: true.
    # config.hydration_enabled = true

    # Maximum number of hydration hints embedded per tool response.
    # config.hydration_max_hints = 5

    # ── Search ────────────────────────────────────────────────────────
    # Narrow the Ruby fallback to these extensions. Unset, it searches
    # every file, as ripgrep does, so the two backends agree.
    # config.search_extensions = %w[rb js erb yml yaml json ts tsx vue svelte haml slim]

    # Where to look for concern source files. Left unset, every
    # app/concerns and app/*/concerns directory is discovered. Setting this replaces
    # that list, so it can narrow as well as reach outside app/.
    # config.concern_paths = %w[app/models/concerns lib/concerns]

    # ── Frontend Framework Detection ─────────────────────────────────
    # Auto-detected from package.json, config/vite.json, etc. Override only if needed.
    # A path outside the app root is read for package.json, lockfiles, bundler config and its tsconfig.json.
    # config.frontend_paths = ["app/frontend", "../web-client"]
  end
end
