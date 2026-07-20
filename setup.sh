#!/bin/bash

# Build System Setup Script
# Rails 8 API + React TypeScript

set -e

# Resolve diretório do script para invocar utilitários relativos
SCRIPT_ROOT="$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"

# Garante permissões executáveis e finais de linha Unix nos scripts
normalize_scripts() {
    chmod +x "$SCRIPT_ROOT/setup.sh" 2>/dev/null || true
    if [ -f "$SCRIPT_ROOT/create_dev_db.sh" ]; then
        chmod +x "$SCRIPT_ROOT/create_dev_db.sh" 2>/dev/null || true
        if command -v dos2unix >/dev/null 2>&1; then
            dos2unix "$SCRIPT_ROOT/create_dev_db.sh" "$SCRIPT_ROOT/setup.sh" >/dev/null 2>&1 || true
        else
            # Remove CRLF caso tenha sido editado no Windows
            sed -i 's/\r$//' "$SCRIPT_ROOT/create_dev_db.sh" || true
            sed -i 's/\r$//' "$SCRIPT_ROOT/setup.sh" || true
        fi
    fi
}

echo "🚀 Setting up Rails 8 API + React TypeScript build system..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Ruby
    if ! command -v ruby &> /dev/null; then
        log_error "Ruby is not installed. Please install Ruby 3.2.0+"
        exit 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 20+"
        exit 1
    fi
    
    # Check PostgreSQL
    if ! command -v psql &> /dev/null; then
        log_warn "PostgreSQL client not found. Make sure PostgreSQL is installed and running."
    fi
    
    # Check Redis
    if ! command -v redis-cli &> /dev/null; then
        log_warn "Redis client not found. Make sure Redis is installed and running."
    fi
    
    log_info "Prerequisites check completed."
}

# Setup backend
setup_backend() {
    log_info "Setting up backend..."
    
    cd backend
    
    # Install gems
    log_info "Installing Ruby gems..."
    bundle install
    
    # Setup database
    log_info "Setting up database..."
    if [ ! -f ".env" ]; then
        cp .env.example .env
        log_warn "Please configure your .env file before continuing."
    fi

    # Provisiona banco usando script dedicado, quando disponível
    if command -v psql &> /dev/null && [ -f "$SCRIPT_ROOT/create_dev_db.sh" ]; then
        log_info "Provisioning PostgreSQL database via create_dev_db.sh..."
        if id -u postgres >/dev/null 2>&1; then
            USE_SUDO=true bash "$SCRIPT_ROOT/create_dev_db.sh" || log_warn "Database provisioning script failed or was skipped."
        else
            USE_SUDO=false bash "$SCRIPT_ROOT/create_dev_db.sh" || log_warn "Database provisioning script failed or was skipped."
        fi
    else
        log_warn "create_dev_db.sh not found or psql missing. Skipping database provisioning."
    fi
    
    # Prepara banco (cria, migra e seed se disponíveis)
    bundle exec rails db:prepare
    
    cd ..
    log_info "Backend setup completed."
}

# Setup frontend
setup_frontend() {
    log_info "Setting up frontend..."
    
    cd frontend
    
    # Install dependencies
    log_info "Installing npm dependencies..."
    npm install
    
    # Copy environment file
    if [ ! -f ".env" ]; then
        cp .env.example .env
        log_warn "Please configure your .env file before continuing."
    fi
    
    cd ..
    log_info "Frontend setup completed."
}

# Setup Docker (optional)
setup_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker found. You can use docker-compose for development."
        log_info "Run: docker-compose up -d"
    else
        log_warn "Docker not found. You'll need to run services manually."
    fi
}

# Create git hooks (optional)
setup_git_hooks() {
    log_info "Setting up git hooks..."
    
    # Pre-commit hook
    cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Pre-commit hook for Rails + React project

echo "Running pre-commit checks..."

# Backend checks
cd backend
if ! bundle exec rubocop; then
    echo "RuboCop failed. Please fix style issues."
    exit 1
fi

# Frontend checks
cd ../frontend
if ! npm run lint; then
    echo "ESLint failed. Please fix style issues."
    exit 1
fi

if ! npm run type-check; then
    echo "TypeScript check failed. Please fix type errors."
    exit 1
fi

echo "Pre-commit checks passed!"
EOF

    chmod +x .git/hooks/pre-commit
    log_info "Git hooks configured."
}

# Main setup function
main() {
    echo "🚀 Rails 8 API + React TypeScript Build System Setup"
    echo "=================================================="
    
    normalize_scripts
    check_prerequisites
    
    # Ask for confirmation
    read -p "Do you want to proceed with the setup? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled."
        exit 0
    fi
    
    # Run setup steps
    setup_backend
    setup_frontend
    setup_docker
    
    # Optional git hooks
    read -p "Do you want to install git hooks? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_git_hooks
    fi
    
    echo
    log_info "✅ Setup completed successfully!"
    echo
    echo "📋 Next steps:"
    echo "1. Configure your .env files in backend/ and frontend/"
    echo "2. Start PostgreSQL and Redis"
    echo "3. Run: docker-compose up -d (or start services manually)"
    echo "4. Backend: cd backend && bundle exec rails server"
    echo "5. Frontend: cd frontend && npm run dev"
    echo
    echo "📚 Documentation: BUILD_SYSTEM.md"
    echo "🎯 Happy coding!"
}

# Run main function
main "$@"