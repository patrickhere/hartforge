# immich companions env TEMPLATE - safe to commit, contains no secret values.
#   ../../render-env.sh immich/companions   ->  root@10.1.0.59:/opt/immich/companions/.env

DB_HOST=immich-db
DB_PORT=5432
DB_USERNAME=postgres
DB_PASSWORD={{ op://Homelab/Immich - postgres database/password }}
DB_DATABASE_NAME=immich

# Auth - API key bypasses login entirely
IMMICH_API_KEY={{ op://Homelab/Immich - API key - companions/credential }}
