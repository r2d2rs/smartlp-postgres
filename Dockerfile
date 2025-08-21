# Custom PostgreSQL 15 with ALL extensions for Chaki System
# This prevents Railway extension limitations and future migration pain
FROM postgres:15

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    postgresql-server-dev-15 \
    curl \
    ca-certificates \
    libssl-dev \
    libcurl4-openssl-dev \
    pkg-config \
    cmake \
    flex \
    bison \
    libreadline-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install pgvector for embeddings (CRITICAL for contextual retrieval)
# Using v0.5.1 for stability with PostgreSQL 15
RUN cd /tmp \
    && git clone --branch v0.5.1 https://github.com/pgvector/pgvector.git \
    && cd pgvector \
    && make OPTFLAGS="" \
    && make install \
    && cd / \
    && rm -rf /tmp/pgvector

# Install temporal_tables for versioning
RUN cd /tmp \
    && git clone https://github.com/arkhipov/temporal_tables.git \
    && cd temporal_tables \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/temporal_tables

# Install pg_cron for scheduled tasks
RUN cd /tmp \
    && git clone https://github.com/citusdata/pg_cron.git \
    && cd pg_cron \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/pg_cron

# Install Apache AGE for graph queries (future-proofing)
RUN cd /tmp \
    && git clone https://github.com/apache/age.git \
    && cd age \
    && git checkout release/PG15/1.5.0 \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/age

# Configure PostgreSQL for our extensions
RUN echo "shared_preload_libraries = 'pg_cron,age'" >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "cron.database_name = 'chaki'" >> /usr/share/postgresql/postgresql.conf.sample

# Copy initialization script
COPY init-extensions.sql /docker-entrypoint-initdb.d/

# Set proper permissions
RUN chmod 644 /docker-entrypoint-initdb.d/init-extensions.sql

# Expose PostgreSQL port
EXPOSE 5432

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD pg_isready -U postgres || exit 1

# Set PGDATA to a subdirectory to avoid Railway volume mount issues
ENV PGDATA=/var/lib/postgresql/data/pgdata

# Labels for documentation
LABEL maintainer="Chaki Team" \
      description="PostgreSQL 15 with pgvector, temporal_tables, pg_cron, and Apache AGE" \
      version="1.0.0"