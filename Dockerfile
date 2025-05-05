FROM alpine:3.21

# Install required packages
RUN apk update && apk add --no-cache \
    bash \
    postgresql-client \
    python3 \
    py3-pip \
    gzip \
    curl

# Create and use a virtual environment for Python packages
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install AWS CLI in the virtual environment
RUN pip3 install --no-cache-dir awscli

# Create directory for the script
WORKDIR /app

# Copy the backup script into the container
COPY postgres_backup.sh .

# Make the script executable
RUN chmod +x postgres_backup.sh

# Set the entrypoint to the backup script
ENTRYPOINT ["/app/postgres_backup.sh"]