#!/bin/sh -e

# TODO posibility of race since this can be called from different pods
# TODO figure out users/priviliges

MYSQL_S3_INITED_FLAG_FILE=/tmp/mysql_s3_is.inited
echo "[$(date -Iseconds)] Started mysqldump"

if ! [ -f "$MYSQL_S3_INITED_FLAG_FILE" ]; then
  echo "[$(date -Iseconds)] mysqls3 is not inited, exiting"
  return 0
fi

filename=$(mktemp)

if [ -z "$MYSQL_DATABASE" ]; then
  MYSQL_DATABASE="--all-databases"
else
  MYSQL_DATABASE="--databases ${MYSQL_DATABASE}"
fi

mysqldump --no-tablespaces -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" ${MYSQL_DATABASE} > "${filename}"
echo "[$(date -Iseconds)] mysqldump finished. Started compression"
gzip "${filename}"
echo "[$(date -Iseconds)] Compression finished"

s3filename_latest="mysqldump_latest.sql.gz"
s3filename_prev="mysqldump_prev.sql.gz"
echo "[$(date -Iseconds)] Started s3 upload"

aws s3api head-object --bucket ${AWS_S3_MYSQL_BUCKET} --key ${s3filename_latest} || latest_not_exist=true
if [ $latest_not_exist ]; then
  echo "[$(date -Iseconds)] Latest version does not exist..."
  aws s3api head-object --bucket ${AWS_S3_MYSQL_BUCKET} --key ${s3filename_prev} || prev_not_exist=true
  if [ $prev_not_exist ]; then
    echo "[$(date -Iseconds)] Prev version does not exist, first upload, uploading new latest.."
    aws s3 cp "${filename}.gz" "s3://${AWS_S3_MYSQL_BUCKET}/${s3filename_latest}"
  else
    echo "[$(date -Iseconds)] Latest version does not exist, but prev exists, shouldn't happen, exiting"
    return 0
  fi
else
  echo "[$(date -Iseconds)] Found existing latest..."
  aws s3api head-object --bucket ${AWS_S3_MYSQL_BUCKET} --key ${s3filename_prev} || prev_not_exist=true
  if [ $prev_not_exist ]; then
    echo "[$(date -Iseconds)] Prev version does not exist..."
  else
    echo "[$(date -Iseconds)] Prev version found, removing..."
    aws s3 rm "s3://${AWS_S3_MYSQL_BUCKET}/${s3filename_prev}"
  fi
  echo "[$(date -Iseconds)] Moving latest to prev..."
  aws s3 mv "s3://${AWS_S3_MYSQL_BUCKET}/${s3filename_latest}" "s3://${AWS_S3_MYSQL_BUCKET}/${s3filename_prev}"
  echo "[$(date -Iseconds)] Removing current latest..."
  aws s3 rm "s3://${AWS_S3_MYSQL_BUCKET}/${s3filename_latest}"
  echo "[$(date -Iseconds)] Uploading new latest..."
  aws s3 cp "${filename}.gz" "s3://${AWS_S3_MYSQL_BUCKET}/${s3filename_latest}"
fi
rm -rf "${filename}.gz"
echo "[$(date -Iseconds)] Done."
