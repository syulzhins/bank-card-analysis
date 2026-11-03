-- 1а. Сколько владельцев счетов имеют карту
SELECT
	COUNT(*) AS owners,
	COUNT (c.card_id) AS with_card,
	ROUND(100.0 * COUNT (card_id)/COUNT(*),1) AS card_pct
FROM clean.dispositions d
	LEFT JOIN clean.cards c ON d.disp_id = c.disp_id
WHERE d.role = 'owner';
-- 4500 владельцев, 892 с картой, 19.8%

-- 1б. Сколько карт каждого типа и какая это доля от всех карт
SELECT
	card_type,
	COUNT(*) AS cards,
	ROUND (100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),1) AS pct
FROM clean.cards c
GROUP BY card_type
ORDER BY pct DESC;
-- classic	659	    73.9%
-- junior	145	    16.3%
-- gold	    88	    9.9%

-- 1в. Выдача карт по годам
SELECT
	EXTRACT (YEAR FROM c.issued_date) AS year,
	COUNT(*) AS total,
	COUNT(*) FILTER (WHERE c.card_type = 'classic') AS classic,
	COUNT(*) FILTER (WHERE c.card_type = 'junior') AS junior,
	COUNT(*) FILTER (WHERE c.card_type = 'gold') AS gold
FROM clean.cards c
GROUP BY year
ORDER BY year;
--  year    total   classic    junior  gold
--  1993	1	    1	         0	    0
--  1994	21	    17	         4	    0
--  1995	63	    42	         17	    4
--  1996	116	    83	         28	    5
--  1997	242	    190	         26	    26
--  1998	449	    326	         70	    53
-- выдача почти удваивается каждый год, половина всех карт выдана в 1998
-- данные заканчиваются 31.12.1998, поэтому у 142 карт, выданных после сентября 1998,
-- нет трёх полных месяцев после выдачи. В будущем сравнении «до и после» их не берём

-- 2. Чем держатели карт отличаются от остальных
-- активность считаем за 1998 год: все счета открыты раньше, окно одинаковое для всех
-- сначала одна строка на клиента (owners + activity), потом средние по группам
WITH owners AS (
	SELECT
		d.client_id,
		d.account_id,
		cl.gender,
		EXTRACT (YEAR FROM AGE (DATE '1998-12-31', cl.birth_date)) AS age,
		c.card_id IS NOT NULL AS has_card
	FROM clean.dispositions d
	JOIN clean.clients cl ON d.client_id = cl.client_id
	LEFT JOIN clean.cards c ON c.disp_id = d.disp_id
	WHERE d.role = 'owner'),
activity AS (
	SELECT
		account_id,
		COUNT(*) / 12.0 AS trans_per_month,
		AVG(balance) AS avg_balance,
		SUM(amount) FILTER (WHERE direction = 'credit') / 12.0 AS income_per_month
	FROM clean.transactions
	WHERE trans_date BETWEEN DATE '1998-01-01' AND DATE '1998-12-31'
	GROUP BY account_id)
SELECT
	o.has_card,
	COUNT(*) AS clients,
	ROUND(AVG(o.age), 1) AS avg_age,
	ROUND(100.0 * COUNT(*) FILTER (WHERE o.gender = 'F') / COUNT(*), 1) AS female_pct,
	ROUND(AVG(a.trans_per_month), 1) AS trans_per_month,
	ROUND(AVG(a.avg_balance)) AS avg_balance,
	ROUND(AVG(a.income_per_month)) AS income_per_month
FROM owners o
LEFT JOIN activity a ON a.account_id = o.account_id
GROUP BY o.has_card;
--  has_card  clients  avg_age  female_pct  trans_per_month  avg_balance  income_per_month
--  false     3608     45.4     49.5        5.9              34602        15510
--  true      892      39.1     47.4        6.4              56571        27198
-- держатели карт моложе на 6 лет, баланс в 1.6 раза больше, поступления в 1.75 раза больше
-- пол почти не отличается, частота операций чуть выше
-- LEFT JOIN с activity: у 8 клиентов не было транзакций в 1998, они остаются в подсчёте
-- это показывает, кто берёт карту, но не доказывает, что карта увеличивает доход