#!/bin/bash
# setup.sh - Complete setup script for Algo Scalper API

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Algo Scalper API Setup ===${NC}"

# Check for required dependencies
check_dependency() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Error: $1 is required but not installed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ $1 is available${NC}"
}

echo -e "${YELLOW}Checking dependencies...${NC}"
check_dependency ruby
check_dependency git
check_dependency psql
check_dependency redis-cli
check_dependency node
check_dependency npm
check_dependency bundle

# Check Ruby version
required_ruby="3.3.4"
current_ruby=$(ruby -e 'puts RUBY_VERSION')
echo -e "${GREEN}Ruby version: $current_ruby${NC}"

# Check PostgreSQL
if ! psql -U postgres -c "SELECT 1" &> /dev/null; then
    echo -e "${RED}Warning: PostgreSQL might not be running or accessible${NC}"
    echo -e "${YELLOW}Please ensure PostgreSQL is running (sudo systemctl start postgresql)${NC}"
fi

# Check Redis
if ! redis-cli ping &> /dev/null; then
    echo -e "${RED}Warning: Redis might not be running${NC}"
    echo -e "${YELLOW}Please ensure Redis is running (sudo systemctl start redis)${NC}"
fi

# Install Ruby dependencies
echo -e "${YELLOW}Installing Ruby dependencies...${NC}"
if [ -f Gemfile ]; then
    bundle install --jobs 4 --retry 3
    echo -e "${GREEN}✓ Bundle installed${NC}"
else
    echo -e "${RED}Error: Gemfile not found${NC}"
    exit 1
fi

# Setup database
echo -e "${YELLOW}Setting up database...${NC}"
rails db:setup
echo -e "${GREEN}✓ Database setup complete${NC}"

# Run migrations
echo -e "${YELLOW}Running migrations...${NC}"
rails db:migrate
echo -e "${GREEN}✓ Database migrations complete${NC}"

# Load recurring jobs
echo -e "${YELLOW}Loading recurring jobs...${NC}"
rails solid_queue:load_recurring
echo -e "${GREEN}✓ Recurring jobs loaded${NC}"

# Create .env file from .env.example if it doesn't exist
if [ ! -f .env ]; then
    echo -e "${YELLOW}Creating .env file from .env.example...${NC}"
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Please edit .env file and add your credentials${NC}"
    echo -e "${YELLOW}Required variables:${NC}"
    echo -e "  - DHAN_CLIENT_ID"
    echo -e "  - DHAN_ACCESS_TOKEN"
    echo -e "  - PLACE_ORDER (set to 'true' for live trading)"
fi

# Check for dashboard directory
if [ -d "dashboard" ]; then
    echo -e "${YELLOW}Checking dashboard dependencies...${NC}"
    cd dashboard
    if [ -f package.json ]; then
        npm install > /dev/null 2>&1
        echo -e "${GREEN}✓ Dashboard dependencies installed${NC}"
    fi
    cd ..
fi

# Create script aliases and helpers
echo -e "${YELLOW}Creating convenience scripts...${NC}"

# Create run.sh for starting the app
cat > run.sh << 'EOF'
#!/bin/bash
echo "Starting Algo Scalper API..."
echo "Running processes:"
echo "  - Rails API (port 3001)"
echo "  - Trading daemon"
echo "  - Solid Queue worker"
echo "  - Next.js dashboard"
echo ""
echo "To stop all processes, press Ctrl+C"
echo ""
./bin/dev
EOF
chmod +x run.sh
echo -e "${GREEN}✓ Created run.sh (use ./run.sh to start all processes)${NC}"

# Create test.sh for running tests
cat > test.sh << 'EOF'
#!/bin/bash
echo "Running Algo Scalper API tests..."
bundle exec rspec
echo "Tests completed"
EOF
chmod +x test.sh
echo -e "${GREEN}✓ Created test.sh (use ./test.sh to run all tests)${NC}"

# Create lint.sh for linting
cat > lint.sh << 'EOF'
#!/bin/bash
echo "Running Algo Scalper API lint checks..."
bundle exec rubocop
echo "Lint check completed"
EOF
chmod +x lint.sh
echo -e "${GREEN}✓ Created lint.sh (use ./lint.sh for linting)${NC}"

echo -e "${GREEN}=== Setup complete! ===${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Edit .env file with your DhanHQ credentials"
echo -e "2. Run ./run.sh to start the application"
echo -e "3. Visit http://localhost:3001 in your browser"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo -e "  ./run.sh             - Start all processes"
echo -e "  ./test.sh            - Run tests"
echo -e "  ./lint.sh            - Run linting"
echo -e "  bundle exec rspec    - Run specific spec"
echo -e "  bin/brakeman --no-pager - Security scan"
echo ""
echo -e "${GREEN}Setup finished successfully!${NC}"
