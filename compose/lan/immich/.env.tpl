# immich host env TEMPLATE - safe to commit, contains no secret values.
#   ../render-env.sh immich   ->  root@10.1.0.59:/opt/immich/.env
#
# DB_PASSWORD is the SAME value as companions/.env.tpl uses - one postgres, two
# consumers. change it in the vault and BOTH must be re-rendered and recomposed.

DB_HOSTNAME=database
DB_USERNAME=postgres
DB_PASSWORD={{ op://Homelab/Immich - postgres database/password }}
DB_DATABASE_NAME=immich

UPLOAD_LOCATION=/usr/src/app/upload
DB_DATA_LOCATION=/var/lib/postgresql/data

TZ=America/Chicago

IMMICH_VERSION=v3.0.3
