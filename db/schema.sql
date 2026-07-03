-- ============================================================================
-- schema.sql
-- PostgreSQL translation of the SQL Server "LocalTestDB" schema (11 tables).
-- Target database: household_test (test DB)
--
-- HOW TO RUN (from the Pi, where your container is named "postgres"):
--   1. Create the database once (connect to the maintenance db first):
--        docker exec -it postgres psql -U admin -d postgres
--        CREATE DATABASE household_test;
--        \q
--   2. Load this schema into it:
--        cat schema.sql | docker exec -i postgres psql -U admin -d household_test
--
-- Translation from SQL Server -> PostgreSQL:
--   int IDENTITY(1,1) -> bigint (Option A: mirror carries the SQL Server ID
--                        verbatim; the consumer inserts it explicitly, Postgres
--                        does NOT generate keys)
--   varbinary(max/64) -> bytea        nvarchar(max) -> text
--   nvarchar(n)/varchar(n) -> varchar(n)   bit -> boolean
--   datetime -> timestamp             decimal(p,s) -> numeric(p,s)
--
-- Names converted to snake_case. Every table has a primary key on id.
-- dim_users has a UNIQUE on user_name_hash; dim_users_s is intentionally FK-FREE (the dim_users FK + ON DELETE CASCADE are
-- omitted) so the replication consumer's atomic swap can use plain TRUNCATE.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Idempotent reset: drop existing mirror tables so this script re-runs cleanly.
-- NOTE: this DESTROYS current data in these tables. Safe here because the
-- consumer repopulates them from SQL Server on its next cycle (they are a
-- rebuildable replication mirror, not a system of record).
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS fact_stock_transactions CASCADE;
DROP TABLE IF EXISTS fact_other_contacts CASCADE;
DROP TABLE IF EXISTS fact_mutual_fund_transactions CASCADE;
DROP TABLE IF EXISTS fact_deposits CASCADE;
DROP TABLE IF EXISTS fact_aliases CASCADE;
DROP TABLE IF EXISTS fact_account_broker_mappings CASCADE;
DROP TABLE IF EXISTS dim_users_s CASCADE;
DROP TABLE IF EXISTS dim_users CASCADE;
DROP TABLE IF EXISTS dim_mutual_funds CASCADE;
DROP TABLE IF EXISTS dim_entities CASCADE;
DROP TABLE IF EXISTS dim_accounts CASCADE;

-- ---------------------------------------------------------------------------
-- Dimension tables
-- ---------------------------------------------------------------------------

CREATE TABLE dim_accounts (
    id                     bigint       NOT NULL,
    account_no             bytea        NOT NULL,
    account_no_hash        bytea        NOT NULL,
    entity_id              integer,
    account_type           text,
    first_holder_id        integer,
    joint_holder1_id       integer,
    joint_holder2_id       integer,
    operation_type         text,
    first_holder_address   bytea,
    nominee1_id            integer,
    nominee2_id            integer,
    cif                    bytea,
    minimum_balance        numeric(18,2),
    open_year              bytea,
    cheque_book_count      integer,
    email_id               bytea,
    contact_no             bytea,
    is_active              boolean,
    passbook_available     boolean,
    online_banking_allowed boolean,
    online_login_available boolean,
    aadhar_linked          boolean,
    brokers_linked         boolean,
    comments               bytea,
    created_date           timestamp,
    modified_date          timestamp,
    CONSTRAINT pk_dim_accounts PRIMARY KEY (id)
);

CREATE TABLE dim_entities (
    id                      bigint       NOT NULL,
    entity_name_hash        bytea        NOT NULL,
    entity_name             bytea,
    entity_branch           bytea,
    address_line1           bytea,
    address_line2           bytea,
    city                    bytea,
    post_code               bytea,
    country                 bytea,
    customer_care_email_id  bytea,
    customer_care_phone_no  bytea,
    customer_care_website   bytea,
    ifsc                    bytea,
    micr                    bytea,
    swift                   bytea,
    iban                    bytea,
    entity_type             varchar(5),
    is_online               boolean,
    registrar_id            integer,
    created_date            timestamp     NOT NULL,
    modified_date           timestamp     NOT NULL,
    CONSTRAINT pk_dim_entities PRIMARY KEY (id)
);

CREATE TABLE dim_mutual_funds (
    id                       bigint       NOT NULL,
    isin_folio_holder_hash   bytea        NOT NULL,
    folio_no                 bytea        NOT NULL,
    scheme_name              bytea        NOT NULL,
    isin                     bytea        NOT NULL,
    scheme_code              bytea        NOT NULL,
    scheme_category          bytea        NOT NULL,
    first_holder_id          integer      NOT NULL,
    joint_holder1_id         integer,
    joint_holder2_id         integer,
    nominee1_id              integer,
    nominee2_id              integer,
    operation_mode           varchar(20),
    total_units_bought       numeric(11,4) NOT NULL,
    total_units_sold         numeric(11,4) NOT NULL,
    total_units_held         numeric(11,4) NOT NULL,
    total_invested_amount    numeric(11,2) NOT NULL,
    total_redeemed_amount    numeric(11,2) NOT NULL,
    total_dividend_received  numeric(11,2) NOT NULL,
    is_active                boolean       NOT NULL,
    linked_entity_id         integer       NOT NULL,
    is_dividend              boolean       NOT NULL,
    is_online                boolean       NOT NULL,
    is_demat                 boolean       NOT NULL,
    comments                 bytea,
    created_date             timestamp,
    modified_date            timestamp,
    CONSTRAINT pk_dim_mutual_funds PRIMARY KEY (id)
);

CREATE TABLE dim_users (
    id              bigint NOT NULL,
    user_name_hash  bytea      NOT NULL,
    gender          char(1),
    age             integer,
    father_id       integer,
    mother_id       integer,
    spouse_id       integer,
    marital_status  char(1),
    is_expired      boolean,
    created_date    timestamp,
    modified_date   timestamp,
    CONSTRAINT pk_dim_users PRIMARY KEY (id),
    CONSTRAINT uq_dim_users_user_name_hash UNIQUE (user_name_hash)
);

CREATE TABLE dim_users_s (
    id                       bigint     NOT NULL,
    user_id                  integer    NOT NULL,
    first_name               bytea,
    last_name                bytea,
    birth_date               bytea,
    birth_city               bytea,
    birth_country            bytea,
    marriage_date            bytea,
    current_address_line1    bytea,
    current_address_line2    bytea,
    current_city             bytea,
    current_post_code        bytea,
    current_country          bytea,
    permanent_address_line1  bytea,
    permanent_address_line2  bytea,
    permanent_city           bytea,
    permanent_post_code      bytea,
    permanent_country        bytea,
    contact_email_id         bytea,
    contact_mobile_no        bytea,
    contact_phone_no         bytea,
    work_email_id            bytea,
    work_mobile_no           bytea,
    work_phone_no            bytea,
    expired_date             bytea,
    pan                      bytea,
    aadhar                   bytea,
    tin                      bytea,
    created_date             timestamp,
    modified_date            timestamp,
    CONSTRAINT pk_dim_users_s PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- Fact tables
-- ---------------------------------------------------------------------------

CREATE TABLE fact_account_broker_mappings (
    id             bigint NOT NULL,
    account_id     integer   NOT NULL,
    broker_id      integer   NOT NULL,
    created_date   timestamp,
    modified_date  timestamp,
    CONSTRAINT pk_fact_account_broker_mappings PRIMARY KEY (id)
);

CREATE TABLE fact_aliases (
    id             bigint NOT NULL,
    record_type    varchar(50),
    record_id      integer,
    alias_name     bytea,
    created_date   timestamp,
    modified_date  timestamp,
    CONSTRAINT pk_fact_aliases PRIMARY KEY (id)
);

CREATE TABLE fact_deposits (
    id                          bigint        NOT NULL,
    deposit_no                  bytea         NOT NULL,
    deposit_no_hash             varchar(64)   NOT NULL,
    entity_id                   integer       NOT NULL,
    linked_account_id           integer,
    first_holder_id             integer       NOT NULL,
    joint_holder1_id            integer,
    joint_holder2_id            integer,
    operation_type              varchar(10)   NOT NULL,
    nominee1_id                 integer,
    nominee2_id                 integer,
    invested_amount             numeric(11,2) NOT NULL,
    interest_rate               numeric(4,2)  NOT NULL,
    start_date                  timestamp,
    expected_maturity_date      timestamp,
    period_years                integer       NOT NULL,
    period_months               integer       NOT NULL,
    period_days                 integer       NOT NULL,
    expected_maturity_amount    numeric(11,2) NOT NULL,
    expected_interest_amount    numeric(11,2) NOT NULL,
    actual_interest_amount      numeric(11,2) NOT NULL,
    actual_maturity_date        timestamp,
    actual_maturity_amount      numeric(11,2) NOT NULL,
    deposit_currency            varchar(10)   NOT NULL,
    deposit_type                varchar(10)   NOT NULL,
    interest_payment_frequency  varchar(10)   NOT NULL,
    deposit_payment_frequency   varchar(10)   NOT NULL,
    closure_type                varchar(10),
    is_booked_online            boolean       NOT NULL,
    is_auto_renewable           boolean       NOT NULL,
    is_renewed                  boolean       NOT NULL,
    is_active                   boolean       NOT NULL,
    is_premature_withdrawal     boolean       NOT NULL,
    broker_id                   integer,
    comments                    bytea,
    created_date                timestamp     NOT NULL,
    modified_date               timestamp     NOT NULL,
    CONSTRAINT pk_fact_deposits PRIMARY KEY (id)
);

CREATE TABLE fact_mutual_fund_transactions (
    id                      bigint NOT NULL,
    fund_id                 integer           NOT NULL,
    transaction_order_hash  bytea,
    exchange                varchar(10),
    transaction_date        timestamp         NOT NULL,
    transaction_type        varchar(10)       NOT NULL,
    realized_amount         numeric(11,2)     NOT NULL,
    transaction_amount      numeric(11,2)     NOT NULL,
    transaction_nav         numeric(11,4)     NOT NULL,
    transaction_units       numeric(11,4)     NOT NULL,
    transaction_stt         numeric(11,2)     NOT NULL,
    transaction_tds         numeric(11,2)     NOT NULL,
    transaction_stamp_duty  numeric(11,2)     NOT NULL,
    broker_id               integer           NOT NULL,
    order_id                bytea,
    trade_id                bytea,
    created_date            timestamp,
    modified_date           timestamp,
    CONSTRAINT pk_fact_mutual_fund_transactions PRIMARY KEY (id)
);

CREATE TABLE fact_other_contacts (
    id             bigint NOT NULL,
    record_type    varchar(50),
    contact_type   varchar(50),
    record_id      integer,
    contact_value  bytea,
    created_date   timestamp   NOT NULL,
    modified_date  timestamp   NOT NULL,
    CONSTRAINT pk_fact_other_contacts PRIMARY KEY (id)
);

CREATE TABLE fact_stock_transactions (
    id                bigint NOT NULL,
    trade_order_hash  bytea,
    holder_id         integer       NOT NULL,
    symbol            bytea         NOT NULL,
    isin              bytea         NOT NULL,
    exchange          varchar(10),
    trade_date        timestamp     NOT NULL,
    trade_type        varchar(10)   NOT NULL,
    trade_amount      numeric(11,2) NOT NULL,
    trade_price       numeric(11,2) NOT NULL,
    trade_quantity    numeric(11,2) NOT NULL,
    nominee_id        integer       NOT NULL,
    linked_entity_id  integer       NOT NULL,
    broker_id         integer       NOT NULL,
    order_id          bytea,
    trade_id          bytea,
    created_date      timestamp,
    modified_date     timestamp,
    CONSTRAINT pk_fact_stock_transactions PRIMARY KEY (id)
);

COMMIT;
