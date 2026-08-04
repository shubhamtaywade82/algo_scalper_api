#!/bin/bash
# setup.sh - Algo Scalper API Setup

set -euo pipefail

echo "=== Algo Scalper API Setup ==="

# Check dependencies
ruby --version | grep -q "3.3.4" || { echo "Ruby 3.3.4 required"; exit 1; }
command -v psql >/dev/null || { echo "PostgreSQL required"; exit 1; }
command -v redis-cli >/dev/null || { echo "Redis required"; exit 1; }
command -v node >/dev/null || { echo "Node.js required"; exit 1; }
command -v npm >/dev/null || { echo "npm required"; exit 1; }
command -v bundle >/dev/null || { echo "Ruby bundler required"; exit 1; }

echo "✓ Dependencies verified"

# Install Ruby gems
echo "Installing Ruby gems..."
bundle install --jobs 4 --retry 3
echo "✓ Gems installed"

# Setup database
echo "Setting up database..."
rails db:setup
rails db:migrate
rails solid_queue:load_recurring
echo "✓ Database configured"

# Environment configuration
if [ ! -f .env ]; then
    cp .env.example .env
    echo "⚠️ Edit .env: set DHAN_CLIENT_ID, DHAN_ACCESS_TOKEN, PLACE_ORDER=true"
fi

# Dashboard setup
if [ -d dashboard ]; then
    echo "Setting up dashboard..."
    cd dashboard && npm install > /dev/null
    cd ..
    echo "✓ Dashboard configured"
fi

# Create convenience scripts
cat > run.sh << 'EOF'
#!/bin/bash
echo "Starting Algo Scalper API (press Ctrl+C to stop)..."
./bin/dev
EOF

cat > test.sh << 'EOF'
#!/bin/bash
echo "Running tests..."
bundle exec rspec
EOF

cat > lint.sh << 'EOF'
#!/bin/bash
echo "Running lint..."
bundle exec rubocop
EOF

chmod +x run.sh test.sh lint.sh
echo "✓ Convenience scripts created"

echo "Setup complete!"
echo "  ./run.sh    - Start all processes"
echo "  ./test.sh    - Run tests"
echo "  ./lint.sh    - Run linting"
