#!/bin/bash

# PostgreSQL operations script for Kubernetes
set -e

OPERATION=${1:-}
MASTER_IP=${2:-}
BACKUP_FILE=${3:-}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_usage() {
    echo "PostgreSQL Operations Script"
    echo ""
    echo "Usage: $0 <operation> <master-ip> [backup-file]"
    echo ""
    echo "Operations:"
    echo "  backup    - Create a manual backup"
    echo "  restore   - Restore from a backup file"
    echo "  shell     - Open PostgreSQL shell"
    echo "  status    - Show database status"
    echo "  logs      - Show PostgreSQL logs"
    echo "  migrate   - Run database migrations"
    echo ""
    echo "Examples:"
    echo "  $0 backup 1.2.3.4"
    echo "  $0 restore 1.2.3.4 /backup/quotesdb-20240101-120000.sql.gz"
    echo "  $0 shell 1.2.3.4"
}

if [ -z "$OPERATION" ] || [ -z "$MASTER_IP" ]; then
    show_usage
    exit 1
fi

case "$OPERATION" in
    backup)
        echo -e "${GREEN}Creating database backup...${NC}"
        ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} <<'BACKUP_SCRIPT'
        kubectl exec -n postgres postgres-0 -- bash -c '
            BACKUP_FILE="/backup/quotesdb-manual-$(date +%Y%m%d-%H%M%S).sql.gz"
            PGPASSWORD=$POSTGRES_PASSWORD pg_dump \
                -U $POSTGRES_USER \
                -d $POSTGRES_DB \
                --verbose \
                --no-owner \
                --no-acl \
                --clean \
                --if-exists \
                | gzip > $BACKUP_FILE
            echo "Backup created: $BACKUP_FILE"
            ls -lh $BACKUP_FILE
        '
BACKUP_SCRIPT
        echo -e "${GREEN}Backup completed!${NC}"
        ;;
        
    restore)
        if [ -z "$BACKUP_FILE" ]; then
            echo -e "${RED}Error: Backup file required for restore operation${NC}"
            show_usage
            exit 1
        fi
        
        echo -e "${YELLOW}WARNING: This will restore the database from: $BACKUP_FILE${NC}"
        echo -e "${YELLOW}All current data will be replaced!${NC}"
        read -p "Are you sure? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            echo "Restore cancelled"
            exit 0
        fi
        
        echo -e "${GREEN}Restoring database...${NC}"
        ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} <<RESTORE_SCRIPT
        kubectl exec -n postgres postgres-0 -- bash -c '
            if [ ! -f "$BACKUP_FILE" ]; then
                echo "Backup file not found: $BACKUP_FILE"
                exit 1
            fi
            
            # Drop existing connections
            PGPASSWORD=\$POSTGRES_PASSWORD psql \
                -U \$POSTGRES_USER \
                -d postgres \
                -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '\$POSTGRES_DB' AND pid <> pg_backend_pid();"
            
            # Restore the backup
            gunzip -c $BACKUP_FILE | PGPASSWORD=\$POSTGRES_PASSWORD psql \
                -U \$POSTGRES_USER \
                -d \$POSTGRES_DB \
                --set ON_ERROR_STOP=on \
                --verbose
            
            echo "Restore completed successfully"
        ' -- --backup-file="$BACKUP_FILE"
RESTORE_SCRIPT
        echo -e "${GREEN}Restore completed!${NC}"
        ;;
        
    shell)
        echo -e "${GREEN}Opening PostgreSQL shell...${NC}"
        echo "Use \\q to exit"
        ssh -t -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} \
            "kubectl exec -it -n postgres postgres-0 -- psql -U quotesdb -d quotesdb"
        ;;
        
    status)
        echo -e "${GREEN}Database Status:${NC}"
        ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} <<'STATUS_SCRIPT'
        echo "=== Pod Status ==="
        kubectl get pods -n postgres
        echo ""
        echo "=== Storage Status ==="
        kubectl get pvc -n postgres
        echo ""
        echo "=== Database Info ==="
        kubectl exec -n postgres postgres-0 -- psql -U quotesdb -d quotesdb -c "
            SELECT version();
            SELECT pg_database_size('quotesdb') as database_size;
            SELECT count(*) as connection_count FROM pg_stat_activity;
        "
        echo ""
        echo "=== Recent Backups ==="
        kubectl exec -n postgres postgres-0 -- ls -lht /backup | head -10
STATUS_SCRIPT
        ;;
        
    logs)
        echo -e "${GREEN}PostgreSQL Logs (last 50 lines):${NC}"
        ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} \
            "kubectl logs -n postgres postgres-0 --tail=50"
        ;;
        
    migrate)
        echo -e "${GREEN}Running database migrations...${NC}"
        ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} <<'MIGRATE_SCRIPT'
        # Get the database URL from secret
        DB_URL=$(kubectl get secret -n quotesdb postgres-connection -o jsonpath='{.data.DATABASE_URL}' | base64 -d)
        
        # Run migrations using a temporary pod
        kubectl run migrate-$RANDOM \
            --image=quotesdb:latest \
            --restart=Never \
            --rm=true \
            -it \
            --env="DATABASE_URL=$DB_URL" \
            -- npm run db:migrate
        
        echo "Migrations completed!"
MIGRATE_SCRIPT
        ;;
        
    *)
        echo -e "${RED}Unknown operation: $OPERATION${NC}"
        show_usage
        exit 1
        ;;
esac