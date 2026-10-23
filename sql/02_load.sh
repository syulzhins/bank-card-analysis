#!/bin/bash


set -e
DATA_DIR="$(cd "$(dirname "$0")/../data" && pwd)"
OPTS="WITH (FORMAT csv, HEADER true, DELIMITER ';')"

psql -d bank \
  -c "\copy raw.account  FROM '$DATA_DIR/account.csv'  $OPTS" \
  -c "\copy raw.card     FROM '$DATA_DIR/card.csv'     $OPTS" \
  -c "\copy raw.client   FROM '$DATA_DIR/client.csv'   $OPTS" \
  -c "\copy raw.disp     FROM '$DATA_DIR/disp.csv'     $OPTS" \
  -c "\copy raw.district FROM '$DATA_DIR/district.csv' $OPTS" \
  -c "\copy raw.loan     FROM '$DATA_DIR/loan.csv'     $OPTS" \
  -c "\copy raw.orders   FROM '$DATA_DIR/order.csv'    $OPTS" \
  -c "\copy raw.trans    FROM '$DATA_DIR/trans.csv'    $OPTS"
