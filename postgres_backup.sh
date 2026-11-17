#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Script for PostgreSQL database backup with S3 or MinIO upload
# Required environment variables:
# - SERVICE_NAME: Name of the service for the backup file naming
# - PGHOST: PostgreSQL host
# - PGPORT: PostgreSQL port
# - PGDATABASE: PostgreSQL database name
# - PGUSER: PostgreSQL username
# - PGPASSWORD: PostgreSQL password
# - S3_BUCKET: S3/MinIO bucket name
# - S3_PREFIX: S3/MinIO prefix/folder path (optional)
# - AWS_ACCESS_KEY_ID: AWS/MinIO access key
# - AWS_SECRET_ACCESS_KEY: AWS/MinIO secret key
# - AWS_DEFAULT_REGION: AWS region (when using AWS S3)
# - USE_MINIO: Set to "true" if using MinIO instead of AWS S3 (optional)
# - MINIO_ENDPOINT: MinIO server endpoint URL (required when USE_MINIO=true)
#
# Usage:
#   postgres_backup.sh           Run backup and upload
#   postgres_backup.sh --check   Validate configuration and print it (secrets
#                                masked) without dumping or uploading anything

CHECK_MODE=false
if [ "$1" = "--check" ]; then
    CHECK_MODE=true
fi

# Print "****" for a set secret, "(not set)" otherwise; never prints the value
mask_secret() {
    if [ -n "$1" ]; then
        echo "****"
    else
        echo "(not set)"
    fi
}

# In check mode, report exactly which required variables are missing
if [ "$CHECK_MODE" = "true" ]; then
    MISSING_VARS=""
    for VAR_NAME in SERVICE_NAME PGHOST PGDATABASE PGUSER PGPASSWORD S3_BUCKET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
        if [ -z "${!VAR_NAME}" ]; then
            MISSING_VARS="${MISSING_VARS} ${VAR_NAME}"
        fi
    done
    if [ -n "$MISSING_VARS" ]; then
        echo "Error: Missing required environment variables:${MISSING_VARS}"
        exit 1
    fi
fi

# Check if required environment variables are set
if [ -z "$SERVICE_NAME" ] || [ -z "$PGDATABASE" ] || [ -z "$PGUSER" ] || \
   [ -z "$PGPASSWORD" ] || [ -z "$PGHOST" ] || [ -z "$S3_BUCKET" ] || \
   [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Error: Required environment variables are not set"
    echo "Required variables: SERVICE_NAME, PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD, S3_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    exit 1
fi

# Check MinIO-specific requirements
if [ "${USE_MINIO}" = "true" ] && [ -z "$MINIO_ENDPOINT" ]; then
    echo "Error: MINIO_ENDPOINT is required when USE_MINIO is set to true"
    exit 1
fi

# Set default values for optional variables
PGPORT=${PGPORT:-5432}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}
USE_MINIO=${USE_MINIO:-false}

# Check mode: print normalized configuration and exit without side effects
# (no pg_dump, no backup files, no upload)
if [ "$CHECK_MODE" = "true" ]; then
    CHECK_ZIP_FILE="${SERVICE_NAME}-$(date +%Y%m%d).sql.gz"
    if [ -z "$S3_PREFIX" ]; then
        CHECK_DESTINATION="s3://${S3_BUCKET}/${CHECK_ZIP_FILE}"
    else
        CHECK_DESTINATION="s3://${S3_BUCKET}/${S3_PREFIX}/${CHECK_ZIP_FILE}"
    fi
    if [ "${USE_MINIO}" = "true" ]; then
        CHECK_STORAGE_TYPE="MinIO"
    else
        CHECK_STORAGE_TYPE="AWS S3"
    fi
    echo "Configuration check passed"
    echo "SERVICE_NAME=${SERVICE_NAME}"
    echo "PGHOST=${PGHOST}"
    echo "PGPORT=${PGPORT}"
    echo "PGDATABASE=${PGDATABASE}"
    echo "PGUSER=${PGUSER}"
    echo "PGPASSWORD=$(mask_secret "$PGPASSWORD")"
    echo "S3_BUCKET=${S3_BUCKET}"
    echo "S3_PREFIX=${S3_PREFIX}"
    echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
    echo "AWS_SECRET_ACCESS_KEY=$(mask_secret "$AWS_SECRET_ACCESS_KEY")"
    echo "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
    echo "USE_MINIO=${USE_MINIO}"
    echo "MINIO_ENDPOINT=${MINIO_ENDPOINT}"
    echo "STORAGE_TYPE=${CHECK_STORAGE_TYPE}"
    echo "S3_DESTINATION=${CHECK_DESTINATION}"
    exit 0
fi

# Set the backup date format (YYYYMMDD)
BACKUP_DATE=$(date +%Y%m%d)

# Create backup directory if it doesn't exist
BACKUP_DIR="/tmp/pg_backups"
mkdir -p $BACKUP_DIR

# Set the backup file name according to the required format
BACKUP_FILE="${SERVICE_NAME}-${BACKUP_DATE}.sql"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"
ZIP_FILE="${BACKUP_FILE}.gz"
ZIP_PATH="${BACKUP_DIR}/${ZIP_FILE}"

echo "Starting PostgreSQL backup for ${SERVICE_NAME} at $(date)"

# Perform PostgreSQL dump
echo "Dumping database ${PGDATABASE}..."
PGPASSWORD=$PGPASSWORD pg_dump -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -F p > $BACKUP_PATH
echo "Database dump completed successfully"

# Compress the SQL file
echo "Compressing backup file..."
gzip -f $BACKUP_PATH
echo "Compression completed: ${ZIP_PATH}"

# Upload to S3 or MinIO
if [ "${USE_MINIO}" = "true" ]; then
    echo "Uploading to MinIO bucket ${S3_BUCKET} at ${MINIO_ENDPOINT}..."
    STORAGE_TYPE="MinIO"
else
    echo "Uploading to AWS S3 bucket ${S3_BUCKET}..."
    STORAGE_TYPE="AWS S3"
fi

if [ -z "$S3_PREFIX" ]; then
    S3_DESTINATION="s3://${S3_BUCKET}/${ZIP_FILE}"
else
    S3_DESTINATION="s3://${S3_BUCKET}/${S3_PREFIX}/${ZIP_FILE}"
fi

# Use AWS CLI to upload the file, with MinIO endpoint if needed
if [ "${USE_MINIO}" = "true" ]; then
    aws s3 cp $ZIP_PATH $S3_DESTINATION --endpoint-url $MINIO_ENDPOINT
else
    aws s3 cp $ZIP_PATH $S3_DESTINATION
fi

echo "Upload to ${STORAGE_TYPE} completed: ${S3_DESTINATION}"

# Clean up local files
echo "Cleaning up temporary files..."
rm -f $ZIP_PATH
echo "Cleanup completed"

echo "Backup process completed successfully at $(date)"