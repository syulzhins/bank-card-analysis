CREATE SCHEMA raw;

CREATE TABLE raw.account (
    account_id  TEXT,
    district_id TEXT,
    frequency   TEXT,
    date        TEXT
);

CREATE TABLE raw.card (
    card_id TEXT,
    disp_id TEXT,
    type    TEXT,
    issued  TEXT
);

CREATE TABLE raw.client (
    client_id    TEXT,
    birth_number TEXT,
    district_id  TEXT
);

CREATE TABLE raw.disp (
    disp_id    TEXT,
    client_id  TEXT,
    account_id TEXT,
    type       TEXT
);

CREATE TABLE raw.district (
    A1  TEXT,
    A2  TEXT,
    A3  TEXT,
    A4  TEXT,
    A5  TEXT,
    A6  TEXT,
    A7  TEXT,
    A8  TEXT,
    A9  TEXT,
    A10 TEXT,
    A11 TEXT,
    A12 TEXT,
    A13 TEXT,
    A14 TEXT,
    A15 TEXT,
    A16 TEXT
);

CREATE TABLE raw.loan (
    loan_id    TEXT,
    account_id TEXT,
    date       TEXT,
    amount     TEXT,
    duration   TEXT,
    payments   TEXT,
    status     TEXT
);

CREATE TABLE raw.orders (
    order_id   TEXT,
    account_id TEXT,
    bank_to    TEXT,
    account_to TEXT,
    amount     TEXT,
    k_symbol   TEXT
);

CREATE TABLE raw.trans (
    trans_id   TEXT,
    account_id TEXT,
    date       TEXT,
    type       TEXT,
    operation  TEXT,
    amount     TEXT,
    balance    TEXT,
    k_symbol   TEXT,
    bank       TEXT,
    account    TEXT
);
