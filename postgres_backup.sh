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