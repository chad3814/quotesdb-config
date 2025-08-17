#!/bin/bash

# Script to clean up a PR environment
set -e

PR_NUMBER=$1

if [ -z "$PR_NUMBER" ]; then
    echo "Usage: $0 <PR_NUMBER>"
    exit 1
fi

# Configuration
PR_NAMESPACE="quotesdb-pr-${PR_NUMBER}"
PR_DATABASE="quotesdb_pr_${PR_NUMBER}"

echo "Cleaning up PR environment #${PR_NUMBER}"

# Delete Kubernetes resources
echo "Deleting Kubernetes namespace: ${PR_NAMESPACE}"
kubectl delete namespace ${PR_NAMESPACE} --ignore-not-found=true

# Drop database
if [ -n "$DATABASE_URL" ]; then
    echo "Dropping database: ${PR_DATABASE}"
    
    # Parse DATABASE_URL
    DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\).*/\1/p')
    DB_USER=$(echo $DATABASE_URL | sed -n 's/.*:\/\/\([^:]*\).*/\1/p')
    
    # Drop database
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -c "DROP DATABASE IF EXISTS ${PR_DATABASE};"
fi

echo "PR environment #${PR_NUMBER} cleaned up successfully!"