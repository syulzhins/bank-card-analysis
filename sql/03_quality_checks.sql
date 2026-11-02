-- Проверка данных в raw перед очисткой

-- 1. Ключи: нет ли дублей и пустых значений

SELECT COUNT(*)                                AS total_rows,
       COUNT(account_id)                       AS not_null_ids,
       COUNT(DISTINCT account_id)              AS unique_ids,
       COUNT(*) FILTER (WHERE account_id = '') AS empty_ids
FROM raw.account;
-- 4500 | 4500 | 4500 | 0

SELECT COUNT(*), COUNT(client_id), COUNT(DISTINCT client_id), COUNT(*) FILTER (WHERE client_id = '')
FROM raw.client;
-- 5369 | 5369 | 5369 | 0

SELECT COUNT(*), COUNT(disp_id), COUNT(DISTINCT disp_id), COUNT(*) FILTER (WHERE disp_id = '')
FROM raw.disp;
-- 5369 | 5369 | 5369 | 0

SELECT COUNT(*), COUNT(card_id), COUNT(DISTINCT card_id), COUNT(*) FILTER (WHERE card_id = '')
FROM raw.card;
-- 892 | 892 | 892 | 0

SELECT COUNT(*), COUNT(loan_id), COUNT(DISTINCT loan_id), COUNT(*) FILTER (WHERE loan_id = '')
FROM raw.loan;
-- 682 | 682 | 682 | 0

SELECT COUNT(*), COUNT(order_id), COUNT(DISTINCT order_id), COUNT(*) FILTER (WHERE order_id = '')
FROM raw.orders;
-- 6471 | 6471 | 6471 | 0

SELECT COUNT(*), COUNT(trans_id), COUNT(DISTINCT trans_id), COUNT(*) FILTER (WHERE trans_id = '')
FROM raw.trans;
-- 1056320 | 1056320 | 1056320 | 0

SELECT COUNT(*), COUNT(a1), COUNT(DISTINCT a1), COUNT(*) FILTER (WHERE a1 = '')
FROM raw.district;
-- 77 | 77 | 77 | 0

-- Во всех таблицах ключи уникальные и заполнены


-- 2. Какие значения встречаются в категориальных столбцах
-- LENGTH нужен, чтобы отличить NULL, пустую строку и пробел

SELECT frequency, LENGTH(frequency) AS len, COUNT(*) AS cnt
FROM raw.account
GROUP BY frequency
ORDER BY cnt DESC;
-- POPLATEK MESICNE 4167, POPLATEK TYDNE 240, POPLATEK PO OBRATU 93

SELECT type, LENGTH(type) AS len, COUNT(*) AS cnt
FROM raw.disp
GROUP BY type
ORDER BY cnt DESC;
-- OWNER 4500, DISPONENT 869. Владельцев столько же, сколько счетов

SELECT type, LENGTH(type) AS len, COUNT(*) AS cnt
FROM raw.card
GROUP BY type
ORDER BY cnt DESC;
-- classic 659, junior 145, gold 88

SELECT status, LENGTH(status) AS len, COUNT(*) AS cnt
FROM raw.loan
GROUP BY status
ORDER BY cnt DESC;
-- C 403, A 203, D 45, B 31. Проблемных кредитов (B и D) 76 из 682

SELECT type, LENGTH(type) AS len, COUNT(*) AS cnt
FROM raw.trans
GROUP BY type
ORDER BY cnt DESC;
-- VYDAJ 634571, PRIJEM 405083, VYBER 16666
-- VYBER в описании датасета нет, смотрим какие у него операции

SELECT type, operation, COUNT(*)
FROM raw.trans
GROUP BY type, operation
ORDER BY type, operation;
-- у VYBER всегда операция VYBER (снятие наличных), у VYDAJ она тоже есть
-- значит VYBER это тоже списание

SELECT operation, LENGTH(operation) AS len, COUNT(*) AS cnt
FROM raw.trans
GROUP BY operation
ORDER BY cnt DESC;
-- 5 операций из описания и пустая строка у 183114 транзакций

SELECT operation, k_symbol, COUNT(*)
FROM raw.trans
WHERE operation = ''
GROUP BY operation, k_symbol;
-- у всех пустых операций k_symbol = UROK, то есть это начисление процентов

SELECT k_symbol, LENGTH(k_symbol) AS len, COUNT(*) AS cnt
FROM raw.trans
GROUP BY k_symbol
ORDER BY cnt DESC;
-- кроме 7 нормальных значений есть три вида пустых:
-- '' 481871, ' ' 53433, NULL 10

SELECT k_symbol, LENGTH(k_symbol) AS len, COUNT(*) AS cnt
FROM raw.orders
GROUP BY k_symbol
ORDER BY cnt DESC;
-- 4 значения и пробел у 1379 строк


-- 3. Все ли ссылки между таблицами ведут на существующие строки
-- LEFT JOIN оставляет строки без пары, у них справа будет NULL

SELECT COUNT(*)
FROM raw.disp d
LEFT JOIN raw.account a ON a.account_id = d.account_id
WHERE a.account_id IS NULL;
-- 0

SELECT COUNT(*)
FROM raw.disp d
LEFT JOIN raw.client c ON c.client_id = d.client_id
WHERE c.client_id IS NULL;
-- 0

SELECT COUNT(*)
FROM raw.card c
LEFT JOIN raw.disp d ON d.disp_id = c.disp_id
WHERE d.disp_id IS NULL;
-- 0

SELECT COUNT(*)
FROM raw.loan l
LEFT JOIN raw.account a ON a.account_id = l.account_id
WHERE a.account_id IS NULL;
-- 0

SELECT COUNT(*)
FROM raw.trans t
LEFT JOIN raw.account a ON a.account_id = t.account_id
WHERE a.account_id IS NULL;
-- 0

SELECT COUNT(*)
FROM raw.account a
LEFT JOIN raw.district d ON d.a1 = a.district_id
WHERE d.a1 IS NULL;
-- 0

SELECT COUNT(*)
FROM raw.client c
LEFT JOIN raw.district d ON d.a1 = c.district_id
WHERE d.a1 IS NULL;
-- 0

-- счета без владельца
SELECT COUNT(*)
FROM raw.account a
WHERE NOT EXISTS (
    SELECT 1
    FROM raw.disp d
    WHERE d.account_id = a.account_id
      AND d.type = 'OWNER'
);
-- 0

-- битых ссылок нет, поэтому в clean можно добавить внешние ключи


-- 4. Проверяем то, что написано в описании датасета

-- на один счёт не больше одного кредита
SELECT account_id, COUNT(*)
FROM raw.loan
GROUP BY account_id
HAVING COUNT(*) > 1;
-- пусто, так и есть

-- на один счёт может быть несколько карт
SELECT d.account_id, COUNT(*)
FROM raw.card c
JOIN raw.disp d ON d.disp_id = c.disp_id
GROUP BY d.account_id
HAVING COUNT(*) > 1;
-- пусто: в данных у каждого счёта максимум одна карта

-- кому выдают карты
SELECT d.type, COUNT(*)
FROM raw.card c
JOIN raw.disp d ON d.disp_id = c.disp_id
GROUP BY d.type;
-- OWNER 892, то есть все карты у владельцев счетов

SELECT COUNT(DISTINCT account_id)
FROM raw.disp
WHERE type = 'DISPONENT';
-- 869 счетов из 4500 имеют второго человека

SELECT COUNT(*)
FROM (
    SELECT account_id
    FROM raw.disp
    WHERE type = 'OWNER'
    GROUP BY account_id
    HAVING COUNT(*) > 1
) x;
-- 0, у каждого счёта ровно один владелец


-- 5. Диапазоны значений
-- даты в формате YYMMDD можно сравнивать как текст, суммы нужно переводить в число

SELECT MIN(date), MAX(date)
FROM raw.trans;
-- 930101 - 981231

SELECT (SELECT MIN(date) || ' - ' || MAX(date) FROM raw.account)                AS accounts,
       (SELECT MIN(date) || ' - ' || MAX(date) FROM raw.loan)                   AS loans,
       (SELECT MIN(LEFT(issued, 6)) || ' - ' || MAX(LEFT(issued, 6)) FROM raw.card) AS cards;
-- счета 930101 - 971229, кредиты 930705 - 981208, карты 931107 - 981229
-- в card.issued после даты идёт время 00:00:00

SELECT MIN(amount::NUMERIC),
       MAX(amount::NUMERIC),
       ROUND(AVG(amount::NUMERIC), 2),
       COUNT(*) FILTER (WHERE amount::NUMERIC = 0)
FROM raw.trans;
-- 0 | 87400 | 5924.15 | 14
-- отрицательных сумм нет, списание или поступление определяется по type

SELECT MIN(balance::NUMERIC), COUNT(*) FILTER (WHERE balance::NUMERIC < 0)
FROM raw.trans;
-- минимум -41125.70, отрицательный баланс в 2999 транзакциях
-- похоже на правду, за минус на счёте есть штрафные проценты (SANKC. UROK)

SELECT COUNT(*) FILTER (WHERE account IS NULL) AS nulls,
       COUNT(*) FILTER (WHERE account = '0')   AS zeros
FROM raw.trans;
-- NULL 760931, '0' 21881. Ноль тут тоже означает, что счёта нет

SELECT a1, a2, a12, a15
FROM raw.district
WHERE a12 !~ '^[0-9.]+$'
   OR a15 !~ '^[0-9.]+$';
-- район 69 (Jesenik): вместо безработицы и преступности за 1995 стоит '?'

-- месяц в birth_number: у мужчин 01-12, у женщин 51-62
SELECT COUNT(*) FILTER (WHERE SUBSTRING(birth_number, 3, 2)::INT BETWEEN 1 AND 12)  AS men,
       COUNT(*) FILTER (WHERE SUBSTRING(birth_number, 3, 2)::INT BETWEEN 51 AND 62) AS women,
       COUNT(*) FILTER (WHERE SUBSTRING(birth_number, 3, 2)::INT NOT BETWEEN 1 AND 12
                          AND SUBSTRING(birth_number, 3, 2)::INT NOT BETWEEN 51 AND 62) AS invalid
FROM raw.client;
-- 2724 | 2645 | 0


-- Что исправить в clean:
-- type VYBER считать списанием
-- пустую operation с k_symbol = UROK назвать interest
-- все пустые k_symbol ('', ' ', NULL) сделать NULL, в orders тоже
-- счёт партнёра '0' сделать NULL
-- '?' в district сделать NULL
-- даты перевести в DATE, у карт убрать время
-- из birth_number достать пол и дату рождения
