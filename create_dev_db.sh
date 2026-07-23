#!/usr/bin/env bash
set -euo pipefail

# =============================================
# CONFIGURAÇÕES INICIAIS
# =============================================

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1; pwd -P)"
DEFAULT_CONFIG_PATH="$SCRIPT_DIR/backend/config/database.yml"
CONFIG_PATH="${1:-${CONFIG_PATH:-$DEFAULT_CONFIG_PATH}}"

USE_SUDO=${USE_SUDO:-true}
PGHOST_SUPER=${PGHOST_SUPER:-localhost}
PGPORT_SUPER=${PGPORT_SUPER:-5432}
PGUSER_SUPER=${PGUSER_SUPER:-postgres}

# =============================================
# VALIDA CONFIG
# =============================================

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "❌ Arquivo de configuração não encontrado: $CONFIG_PATH"
  echo "Use: bash create_dev_db.sh [caminho_para_database.yml]"
  exit 1
fi

# =============================================
# SOLICITA SENHA DO POSTGRES
# =============================================

if [[ "$USE_SUDO" == "true" ]]; then
  sudo -v || true
  if [[ -z "${PGPASSWORD_SUPER:-}" ]]; then
    read -s -p "🔑 Senha do Postgres (usuário postgres): " PGPASSWORD_SUPER
    echo
  fi
else
  if [[ -z "${PGPASSWORD_SUPER:-}" ]]; then
    read -s -p "🔑 Senha do Postgres (superusuário $PGUSER_SUPER): " PGPASSWORD_SUPER
    echo
  fi

  export PGPASSWORD="$PGPASSWORD_SUPER"
  PGPASSFILE="$(mktemp)"
  echo "$PGHOST_SUPER:$PGPORT_SUPER:*:$PGUSER_SUPER:$PGPASSWORD_SUPER" > "$PGPASSFILE"
  chmod 600 "$PGPASSFILE"
  export PGPASSFILE
  trap 'rm -f "$PGPASSFILE"' EXIT
fi

# =============================================
# LÊ O ARQUIVO database.yml
# =============================================

# database.yml agora usa `url:` (DATABASE_URL) em vez de host/database/username/
# password soltos (delivery-and-observability 1.3). Lê a URL do bloco development
# (resolvendo o ENV.fetch com o mesmo default) e a decompõe.
read_yaml() {
  ruby -ryaml -ruri -rerb -e "
raw = ERB.new(File.read('$CONFIG_PATH')).result
cfg = YAML.safe_load(raw, aliases: true)
url = cfg.dig('development', 'url') or abort('development.url ausente em database.yml')
u = URI.parse(url)
host = (u.host && !u.host.empty?) ? u.host : 'localhost'
db = u.path.sub(%r{^/}, '')
user = u.user
pass = u.password
puts [host, db, user, pass].join('|')
"
}

IFS='|' read -r HOST DB DB_USER PASS <<< "$(read_yaml)"
HOST="${HOST:-localhost}"

# =============================================
# EXECUTA COMO SUPERUSUÁRIO POSTGRES
# =============================================

execute_as_postgres() {
  sudo -u postgres bash -c "
    set -euo pipefail
    export PGPASSWORD='${PGPASSWORD_SUPER}'
    export PGHOST='${PGHOST_SUPER}'
    export PGPORT='${PGPORT_SUPER}'
    export DB='${DB}'
    export DB_USER='${DB_USER}'
    export PASS='${PASS}'

    echo '🔍 Testando conexão com Postgres...'
    if ! psql -h \"\$PGHOST\" -p \"\$PGPORT\" -U postgres -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null 2>&1; then
      echo '⚠️  Falha ao conectar via TCP em \$PGHOST:\$PGPORT. Tentando socket local...'
      if ! psql -U postgres -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null 2>&1; then
        echo '❌ Não foi possível conectar ao Postgres. Verifique pg_hba.conf e senha.'
        exit 1
      fi
      USE_TCP=0
    else
      USE_TCP=1
    fi

    run_psql() {
      if [[ \"\$USE_TCP\" -eq 1 ]]; then
        psql -h \"\$PGHOST\" -p \"\$PGPORT\" -U postgres -v ON_ERROR_STOP=1 \"\$@\"
      else
        psql -U postgres -v ON_ERROR_STOP=1 \"\$@\"
      fi
    }

    run_createdb() {
      if [[ \"\$USE_TCP\" -eq 1 ]]; then
        createdb -h \"\$PGHOST\" -p \"\$PGPORT\" -U postgres --no-password \"\$@\"
      else
        createdb \"\$@\"
      fi
    }

    # =============================================
    # CRIA ROLE SE NÃO EXISTIR
    # =============================================
    ROLE_EXISTS=\$(run_psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='\$DB_USER'\")
    if [[ \"\$ROLE_EXISTS\" != '1' ]]; then
      echo '👤 Criando usuário' \$DB_USER
      run_psql -c \"CREATE ROLE \\\"\$DB_USER\\\" LOGIN PASSWORD '\$PASS';\"
    else
      echo '✅ Usuário \$DB_USER já existe.'
    fi

    run_psql -c \"ALTER ROLE \\\"\$DB_USER\\\" CREATEDB LOGIN;\"

    # =============================================
    # CRIA DATABASE SE NÃO EXISTIR
    # =============================================
    DB_EXISTS=\$(run_psql -tAc \"SELECT 1 FROM pg_database WHERE datname='\$DB'\")
    if [[ \"\$DB_EXISTS\" != '1' ]]; then
      echo '🗃️ Criando banco' \$DB
      run_createdb -O \"\$DB_USER\" \"\$DB\"
    else
      echo '✅ Banco \$DB já existe.'
    fi

    # =============================================
    # ATRIBUI PRIVILÉGIOS
    # =============================================
    echo '🔒 Garantindo privilégios...'
    run_psql -d \"\$DB\" -c \"GRANT ALL PRIVILEGES ON DATABASE \\\"\$DB\\\" TO \\\"\$DB_USER\\\";\"
    run_psql -d \"\$DB\" -c \"ALTER SCHEMA public OWNER TO \\\"\$DB_USER\\\";\"
    run_psql -d \"\$DB\" -c \"GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \\\"\$DB_USER\\\";\"
    run_psql -d \"\$DB\" -c \"GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \\\"\$DB_USER\\\";\"
    run_psql -d \"\$DB\" -c \"GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO \\\"\$DB_USER\\\";\"
    run_psql -d \"\$DB\" -c \"ALTER DEFAULT PRIVILEGES FOR ROLE \\\"\$DB_USER\\\" IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO \\\"\$DB_USER\\\";\"
    run_psql -d \"\$DB\" -c \"ALTER DEFAULT PRIVILEGES FOR ROLE \\\"\$DB_USER\\\" IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO \\\"\$DB_USER\\\";\"
    run_psql -d \"\$DB\" -c \"ALTER DEFAULT PRIVILEGES FOR ROLE \\\"\$DB_USER\\\" IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO \\\"\$DB_USER\\\";\"

    echo '✅ Banco '\$DB' e usuário '\$DB_USER' configurados com sucesso.'
  "
}

# =============================================
# EXECUÇÃO PRINCIPAL
# =============================================

if [[ "$USE_SUDO" == "true" ]]; then
  execute_as_postgres
else
  echo "⚙️  Modo sem sudo ainda não implementado nesta versão simplificada."
fi
