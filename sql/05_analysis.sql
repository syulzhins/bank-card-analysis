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

-- 3. Меняется ли активность клиента после получения карты
-- сравниваем одних и тех же клиентов: 3 месяца до выдачи и 3 месяца после
-- берём карты, выданные до 30.09.1998, чтобы у всех было 3 полных месяца «после»
WITH eligible_cards AS (
	SELECT
		c.card_id,
		d.account_id,
		c.issued_date
	FROM clean.cards c
	JOIN clean.dispositions d ON c.disp_id = d.disp_id
	WHERE c.issued_date <= DATE '1998-09-30'
),
window_transactions AS (
	SELECT
		ec.card_id,
		ec.issued_date,
		t.trans_date,
		t.direction,
		t.amount,
		t.balance
	FROM eligible_cards ec
	JOIN clean.transactions t ON ec.account_id = t.account_id
		AND t.trans_date >= ec.issued_date - INTERVAL '3 months'
		AND t.trans_date < ec.issued_date + INTERVAL '3 months'
),
card_stats AS (
	SELECT
		wt.card_id,
		COUNT(*) FILTER (WHERE wt.trans_date < wt.issued_date) / 3.0 AS trans_before,
		COUNT(*) FILTER (WHERE wt.trans_date >= wt.issued_date) / 3.0 AS trans_after,
		SUM(wt.amount) FILTER (WHERE wt.trans_date < wt.issued_date AND wt.direction = 'credit') / 3.0 AS income_before,
		SUM(wt.amount) FILTER (WHERE wt.trans_date >= wt.issued_date AND wt.direction = 'credit') / 3.0 AS income_after,
		AVG(wt.balance) FILTER (WHERE wt.trans_date < wt.issued_date) AS balance_before,
		AVG(wt.balance) FILTER (WHERE wt.trans_date >= wt.issued_date) AS balance_after
	FROM window_transactions wt
	GROUP BY wt.card_id
)
SELECT
	COUNT(*) AS cards,
	ROUND(AVG(cs.trans_before), 1) AS avg_trans_before,
	ROUND(AVG(cs.trans_after), 1) AS avg_trans_after,
	ROUND(AVG(cs.income_before), 0) AS avg_income_before,
	ROUND(AVG(cs.income_after), 0) AS avg_income_after,
	ROUND(AVG(cs.balance_before), 0) AS avg_balance_before,
	ROUND(AVG(cs.balance_after), 0) AS avg_balance_after
FROM card_stats cs;
--  cards avg_trans_before  avg_trans_after avg_income_before avg_income_after avg_balance_before avg_balance_after
--  750         6.6             6.5              29551              27435           56418             54349
-- после выдачи карты активность не выросла: операций столько же, баланс даже чуть меньше
-- уже до выдачи держатели карт получали около 29.5 тыс. в месяц, примерно вдвое больше,
-- чем клиенты без карты в 1998 (15.5 тыс., запрос 2). Периоды разные, сравнение приблизительное
-- значит, карту берут уже активные клиенты, а не карта делает их активнее
-- ограничения: окно 3 месяца короткое, -4..-7% может быть сезонностью, контрольной группы нет

-- 3б. Пользуются ли клиенты картой после получения
-- те же карты и то же окно, что в запросе 3, считаем снятия по карте (card_withdrawal)
-- до выдачи их должно быть 0, иначе в данных ошибка
WITH eligible_cards AS (
	SELECT
		c.card_id,
		d.account_id,
		c.issued_date
	FROM clean.cards c
	JOIN clean.dispositions d ON c.disp_id = d.disp_id
	WHERE c.issued_date <= DATE '1998-09-30'
),
window_transactions AS (
	SELECT
		ec.card_id,
		ec.issued_date,
		t.trans_date,
		t.operation
	FROM eligible_cards ec
	JOIN clean.transactions t ON ec.account_id = t.account_id
		AND t.trans_date >= ec.issued_date - INTERVAL '3 months'
		AND t.trans_date < ec.issued_date + INTERVAL '3 months'
)
SELECT
	COUNT(*) FILTER (WHERE wt.operation = 'card_withdrawal' AND wt.trans_date < wt.issued_date) AS card_withdrawals_before,
	COUNT(*) FILTER (WHERE wt.operation = 'card_withdrawal' AND wt.trans_date >= wt.issued_date) AS card_withdrawals_after,
	COUNT(DISTINCT wt.card_id) FILTER (WHERE wt.operation = 'card_withdrawal' AND wt.trans_date >= wt.issued_date) AS cards_used,
	COUNT(DISTINCT wt.card_id) AS cards
FROM window_transactions wt;
--  card_withdrawals_before  card_withdrawals_after  cards_used  cards
--  0                        1417                    519         750
-- до выдачи снятий по карте нет, данные согласованы
-- за 3 месяца после выдачи картой воспользовались 519 из 750 клиентов (69%)
-- общее число операций при этом не выросло (запрос 3): карта заменяет часть обычных операций, а не добавляет новые

-- 4. Кому предлагать карту
-- карта не делает клиента активнее (запрос 3), поэтому ищем клиентов без карты,
-- которые по деньгам уже похожи на держателей карт
-- правило: поступления и баланс не ниже, чем у нижней четверти держателей, и нет проблемного кредита
-- активность считаем за 1998, как в запросе 2
WITH owners AS (
	SELECT
		d.client_id,
		d.account_id,
		cl.gender,
		EXTRACT(YEAR FROM AGE(DATE '1998-12-31', cl.birth_date)) AS age,
		c.card_id IS NOT NULL AS has_card
	FROM clean.dispositions d
	JOIN clean.clients cl ON d.client_id = cl.client_id
	LEFT JOIN clean.cards c ON c.disp_id = d.disp_id
	WHERE d.role = 'owner'
),
activity AS (
	SELECT
		account_id,
		COUNT(*) / 12.0 AS trans_per_month,
		AVG(balance) AS avg_balance,
		SUM(amount) FILTER (WHERE direction = 'credit') / 12.0 AS income_per_month
	FROM clean.transactions
	WHERE trans_date BETWEEN DATE '1998-01-01' AND DATE '1998-12-31'
	GROUP BY account_id
),
client_profiles AS (
	SELECT
		o.client_id,
		o.account_id,
		o.gender,
		o.age,
		o.has_card,
		a.trans_per_month,
		a.avg_balance,
		a.income_per_month,
		COALESCE(l.is_problem, false) AS has_problem_loan
	FROM owners o
	LEFT JOIN activity a ON a.account_id = o.account_id
	LEFT JOIN clean.loans l ON l.account_id = o.account_id
),
thresholds AS (
	SELECT
		PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY cp.income_per_month) AS min_income,
		PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY cp.avg_balance) AS min_balance
	FROM client_profiles cp
	WHERE cp.has_card
)
SELECT
	COUNT(*) AS target_clients,
	ROUND(AVG(cp.age), 1) AS avg_age,
	ROUND(AVG(cp.income_per_month)) AS avg_income,
	ROUND(AVG(cp.avg_balance)) AS avg_balance
FROM client_profiles cp
CROSS JOIN thresholds th
WHERE NOT cp.has_card
	AND cp.income_per_month >= th.min_income
	AND cp.avg_balance >= th.min_balance
	AND NOT cp.has_problem_loan;
-- пороги: поступления от 16 860 в месяц, средний баланс от 44 832
--  target_clients  avg_age  avg_income  avg_balance
--  649             40.4     36187       61452
-- 649 клиентов из 3608 без карты (18%) подходят под профиль держателя карты
-- поступления и баланс у них даже выше, чем в среднем у держателей (27 198 и 56 571, запрос 2)
-- у 9 клиентов нет поступлений за 1998, сравнение с NULL их отбрасывает, это нормально

-- 4б. Проверка правила: сколько настоящих держателей карт под него подходят
-- если правило хорошее, держателей карт в нём должно быть заметно больше, чем остальных
-- CTE те же, что в запросе 4, меняется только финальный SELECT
WITH owners AS (
	SELECT
		d.client_id,
		d.account_id,
		c.card_id IS NOT NULL AS has_card
	FROM clean.dispositions d
	LEFT JOIN clean.cards c ON c.disp_id = d.disp_id
	WHERE d.role = 'owner'
),
activity AS (
	SELECT
		account_id,
		AVG(balance) AS avg_balance,
		SUM(amount) FILTER (WHERE direction = 'credit') / 12.0 AS income_per_month
	FROM clean.transactions
	WHERE trans_date BETWEEN DATE '1998-01-01' AND DATE '1998-12-31'
	GROUP BY account_id
),
client_profiles AS (
	SELECT
		o.client_id,
		o.has_card,
		a.avg_balance,
		a.income_per_month,
		COALESCE(l.is_problem, false) AS has_problem_loan
	FROM owners o
	LEFT JOIN activity a ON a.account_id = o.account_id
	LEFT JOIN clean.loans l ON l.account_id = o.account_id
),
thresholds AS (
	SELECT
		PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY cp.income_per_month) AS min_income,
		PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY cp.avg_balance) AS min_balance
	FROM client_profiles cp
	WHERE cp.has_card
)
SELECT
	cp.has_card,
	COUNT(*) AS clients,
	COUNT(*) FILTER (WHERE cp.income_per_month >= th.min_income
		AND cp.avg_balance >= th.min_balance
		AND NOT cp.has_problem_loan) AS match_rule,
	ROUND(100.0 * COUNT(*) FILTER (WHERE cp.income_per_month >= th.min_income
		AND cp.avg_balance >= th.min_balance
		AND NOT cp.has_problem_loan) / COUNT(*), 1) AS match_pct
FROM client_profiles cp
CROSS JOIN thresholds th
GROUP BY cp.has_card
ORDER BY cp.has_card DESC;
--  has_card  clients  match_rule  match_pct
--  true      892      539         60.4
--  false     3608     649         18.0
-- под правило подходят 60% держателей карт и 18% остальных клиентов
-- правило хорошо отделяет держателей от остальных, значит, сегмент из 649 клиентов выбран осмысленно
-- 40% держателей правило не проходят: карту берут и менее обеспеченные клиенты, правило их не ловит
