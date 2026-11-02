-- Слой clean: данные из raw с нормальными типами и понятными значениями
-- Скрипт можно запускать повторно, схема каждый раз создаётся заново

DROP SCHEMA IF EXISTS clean CASCADE;
CREATE SCHEMA clean;


-- Районы
-- у района 69 вместо данных за 1995 стоит '?', заменяем на NULL
CREATE TABLE clean.districts AS
SELECT a1::INTEGER               AS district_id,
       a2                        AS district_name,
       a3                        AS region,
       a4::INTEGER               AS population,
       a9::INTEGER               AS num_cities,
       a10::NUMERIC              AS urban_ratio_pct,
       a11::INTEGER              AS avg_salary,
       NULLIF(a12, '?')::NUMERIC AS unemployment_1995_pct,
       a13::NUMERIC              AS unemployment_1996_pct,
       a14::INTEGER              AS entrepreneurs_per_1000,
       NULLIF(a15, '?')::INTEGER AS crimes_1995,
       a16::INTEGER              AS crimes_1996
FROM raw.district;

ALTER TABLE clean.districts ADD PRIMARY KEY (district_id);


-- Клиенты
-- birth_number это YYMMDD, у женщин к месяцу прибавлено 50
-- все клиенты родились в 1911-1987, поэтому год = 1900 + YY
CREATE TABLE clean.clients AS
SELECT client_id::INTEGER AS client_id,
       CASE WHEN SUBSTRING(birth_number, 3, 2)::INTEGER > 50 THEN 'F' ELSE 'M' END AS gender,
       MAKE_DATE(
           1900 + LEFT(birth_number, 2)::INTEGER,
           SUBSTRING(birth_number, 3, 2)::INTEGER
               - CASE WHEN SUBSTRING(birth_number, 3, 2)::INTEGER > 50 THEN 50 ELSE 0 END,
           RIGHT(birth_number, 2)::INTEGER
       ) AS birth_date,
       district_id::INTEGER AS district_id
FROM raw.client;

ALTER TABLE clean.clients ADD PRIMARY KEY (client_id);
ALTER TABLE clean.clients ADD FOREIGN KEY (district_id) REFERENCES clean.districts (district_id);


-- Счета
-- district_id у счёта это район отделения, а не где живёт клиент
CREATE TABLE clean.accounts AS
SELECT account_id::INTEGER  AS account_id,
       district_id::INTEGER AS branch_district_id,
       CASE frequency
           WHEN 'POPLATEK MESICNE'   THEN 'monthly'
           WHEN 'POPLATEK TYDNE'     THEN 'weekly'
           WHEN 'POPLATEK PO OBRATU' THEN 'after_transaction'
       END AS statement_frequency,
       TO_DATE('19' || date, 'YYYYMMDD') AS opened_date
FROM raw.account;

ALTER TABLE clean.accounts ADD PRIMARY KEY (account_id);
ALTER TABLE clean.accounts ADD FOREIGN KEY (branch_district_id) REFERENCES clean.districts (district_id);


-- Кто имеет доступ к счёту: owner (владелец) или disponent
CREATE TABLE clean.dispositions AS
SELECT disp_id::INTEGER    AS disp_id,
       client_id::INTEGER  AS client_id,
       account_id::INTEGER AS account_id,
       LOWER(type)         AS role
FROM raw.disp;

ALTER TABLE clean.dispositions ADD PRIMARY KEY (disp_id);
ALTER TABLE clean.dispositions ADD FOREIGN KEY (client_id) REFERENCES clean.clients (client_id);
ALTER TABLE clean.dispositions ADD FOREIGN KEY (account_id) REFERENCES clean.accounts (account_id);


-- Карты
-- в issued после даты идёт время, берём только первые 6 символов
CREATE TABLE clean.cards AS
SELECT card_id::INTEGER AS card_id,
       disp_id::INTEGER AS disp_id,
       type             AS card_type,
       TO_DATE('19' || LEFT(issued, 6), 'YYYYMMDD') AS issued_date
FROM raw.card;

ALTER TABLE clean.cards ADD PRIMARY KEY (card_id);
ALTER TABLE clean.cards ADD FOREIGN KEY (disp_id) REFERENCES clean.dispositions (disp_id);


-- Кредиты
-- B и D это проблемные кредиты (не выплачен или есть долг)
CREATE TABLE clean.loans AS
SELECT loan_id::INTEGER    AS loan_id,
       account_id::INTEGER AS account_id,
       TO_DATE('19' || date, 'YYYYMMDD') AS loan_date,
       amount::NUMERIC     AS amount,
       duration::INTEGER   AS duration_months,
       payments::NUMERIC   AS monthly_payment,
       status,
       CASE status
           WHEN 'A' THEN 'finished_ok'
           WHEN 'B' THEN 'finished_not_paid'
           WHEN 'C' THEN 'running_ok'
           WHEN 'D' THEN 'running_in_debt'
       END AS status_desc,
       status IN ('B', 'D') AS is_problem
FROM raw.loan;

ALTER TABLE clean.loans ADD PRIMARY KEY (loan_id);
ALTER TABLE clean.loans ADD FOREIGN KEY (account_id) REFERENCES clean.accounts (account_id);


-- Автоплатежи
-- пустое назначение записано пробелом, CASE без ELSE сделает из него NULL
CREATE TABLE clean.standing_orders AS
SELECT order_id::INTEGER   AS order_id,
       account_id::INTEGER AS account_id,
       bank_to,
       account_to,
       amount::NUMERIC     AS amount,
       CASE TRIM(k_symbol)
           WHEN 'POJISTNE' THEN 'insurance'
           WHEN 'SIPO'     THEN 'household'
           WHEN 'LEASING'  THEN 'leasing'
           WHEN 'UVER'     THEN 'loan_payment'
       END AS purpose
FROM raw.orders;

ALTER TABLE clean.standing_orders ADD PRIMARY KEY (order_id);
ALTER TABLE clean.standing_orders ADD FOREIGN KEY (account_id) REFERENCES clean.accounts (account_id);


-- Транзакции
-- VYBER в type это снятие наличных, считаем как debit
-- пустая operation бывает только у начисления процентов (k_symbol = UROK)
-- пустые k_symbol, банк и счёт партнёра (в том числе '0') становятся NULL
CREATE TABLE clean.transactions AS
SELECT trans_id::INTEGER   AS trans_id,
       account_id::INTEGER AS account_id,
       TO_DATE('19' || date, 'YYYYMMDD') AS trans_date,
       CASE type
           WHEN 'PRIJEM' THEN 'credit'
           WHEN 'VYDAJ'  THEN 'debit'
           WHEN 'VYBER'  THEN 'debit'
       END AS direction,
       CASE
           WHEN operation = 'VYBER KARTOU'   THEN 'card_withdrawal'
           WHEN operation = 'VKLAD'          THEN 'cash_deposit'
           WHEN operation = 'PREVOD Z UCTU'  THEN 'transfer_in'
           WHEN operation = 'VYBER'          THEN 'cash_withdrawal'
           WHEN operation = 'PREVOD NA UCET' THEN 'transfer_out'
           WHEN NULLIF(operation, '') IS NULL AND k_symbol = 'UROK' THEN 'interest'
       END AS operation,
       amount::NUMERIC  AS amount,
       balance::NUMERIC AS balance,
       CASE TRIM(k_symbol)
           WHEN 'POJISTNE'    THEN 'insurance'
           WHEN 'SLUZBY'      THEN 'statement_fee'
           WHEN 'UROK'        THEN 'interest'
           WHEN 'SANKC. UROK' THEN 'penalty_interest'
           WHEN 'SIPO'        THEN 'household'
           WHEN 'DUCHOD'      THEN 'pension'
           WHEN 'UVER'        THEN 'loan_payment'
       END AS purpose,
       NULLIF(bank, '') AS partner_bank,
       NULLIF(NULLIF(account, ''), '0') AS partner_account
FROM raw.trans;

ALTER TABLE clean.transactions ADD PRIMARY KEY (trans_id);
ALTER TABLE clean.transactions ADD FOREIGN KEY (account_id) REFERENCES clean.accounts (account_id);

-- индексы под частые JOIN и фильтры по дате
-- для первичных ключей индекс создаётся сам, для внешних нет
CREATE INDEX ON clean.transactions (account_id, trans_date);
CREATE INDEX ON clean.dispositions (account_id);
CREATE INDEX ON clean.dispositions (client_id);
CREATE INDEX ON clean.cards (disp_id);


-- Проверка: число строк совпадает с raw
SELECT 'transactions' AS t,
       (SELECT COUNT(*) FROM raw.trans)          AS raw_rows,
       (SELECT COUNT(*) FROM clean.transactions) AS clean_rows
UNION ALL
SELECT 'clients', (SELECT COUNT(*) FROM raw.client), (SELECT COUNT(*) FROM clean.clients)
UNION ALL
SELECT 'cards', (SELECT COUNT(*) FROM raw.card), (SELECT COUNT(*) FROM clean.cards);

-- Проверка: всем транзакциям нашлось направление и операция
SELECT COUNT(*) FILTER (WHERE direction IS NULL) AS direction_nulls,
       COUNT(*) FILTER (WHERE operation IS NULL) AS operation_nulls
FROM clean.transactions;
