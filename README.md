# Custom PostgreSQL for Chaki System

Custom PostgreSQL 15 Docker image with essential extensions for the Chaki institutional investment analysis platform.

## 🚀 Extensions Included

- **pgvector v0.5.1**: Vector similarity search for embeddings
- **temporal_tables**: Temporal versioning for audit trails
- **Apache AGE**: Graph database capabilities
- **pg_cron**: Scheduled jobs and maintenance
- **uuid-ossp**: UUID generation
- **pgcrypto**: Cryptographic functions
- **unaccent**: Text search improvements

## 📦 Railway Deployment

This image is designed for Railway deployment with the Chaki system.

### Automatic Deployment

Railway will automatically build and deploy this image when connected to this repository.

### Manual Build

```bash
docker build -t chaki-postgres .
docker run -d \
  -p 5432:5432 \
  -e POSTGRES_DB=chaki \
  -e POSTGRES_USER=chaki_user \
  -e POSTGRES_PASSWORD=secure_password \
  chaki-postgres
```

## 🔧 Configuration

The image automatically initializes all extensions on startup via `init-extensions.sql`.

### Verify Extensions

```sql
SELECT * FROM check_extensions();
```

## 🏗️ Architecture

Built for the Chaki system's requirements:
- **Contextual Retrieval**: 67% better accuracy with pgvector
- **Multi-tenant**: Row Level Security support
- **Temporal Data**: Complete audit trails
- **Graph Queries**: Apache AGE for relationships
- **Scheduled Tasks**: pg_cron for maintenance

## 🔐 Security

- Always use strong passwords
- Enable SSL in production
- Restrict network access
- Regular backups recommended

## 📊 Performance

Optimized for:
- Vector searches <100ms
- Concurrent connections: 100+
- Large document processing
- Hybrid search (BM25 + vector)

## 🛠️ Maintenance

The image includes health checks and automatic recovery mechanisms for Railway.

## 📝 License

Part of the Chaki system - Private and confidential
