# Spark Chroma Deployment

This directory contains the configuration to deploy Chroma vector database for Spark.

## Quick Deploy to Railway

1. **Install Railway CLI:**
   ```bash
   npm install -g @railway/cli
   ```

2. **Login to Railway:**
   ```bash
   railway login
   ```

3. **Deploy from this directory:**
   ```bash
   cd chroma-deployment
   railway login
   railway new --name spark-chroma
   railway up
   ```

4. **Get your deployment URL:**
   ```bash
   railway domain
   ```

## Alternative: One-Click Deploy

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/chroma-db)

## Environment Variables (Optional)

- `CHROMA_HOST`: Host to bind to (default: 0.0.0.0)
- `CHROMA_PORT`: Port to bind to (default: 8000)  
- `IS_PERSISTENT`: Enable data persistence (default: TRUE)

## Testing Your Deployment

Once deployed, test with:
```bash
curl https://your-railway-url.up.railway.app/api/v1/heartbeat
```

Should return: `{"nanosecond heartbeat": ...}`

## Cost Estimate

Railway Hobby Plan:
- $5/month for 512MB RAM
- Includes 500 hours (more than enough)
- Perfect for development and early production