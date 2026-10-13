-- ==============================================================================
-- Fulfilment Database Schema Initialization Script
-- Database: orders_db
-- Target: PostgreSQL 12+
-- Usage:
--   psql -U postgres -h localhost -p 5432 -d orders_db -f sql/init_database.sql
-- ==============================================================================

-- 1. Create Sequence for ERP Order Numbers (e.g., ERP-2026-000001)
CREATE SEQUENCE IF NOT EXISTS order_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- 2. Create Header Table: sales_order
CREATE TABLE IF NOT EXISTS sales_order (
    order_number        VARCHAR(30)     PRIMARY KEY,
    opportunity_id      VARCHAR(18)     NOT NULL,
    account_id          VARCHAR(18)     NOT NULL,
    account_name        VARCHAR(150)    NOT NULL,
    account_number      VARCHAR(30),
    contact_name        VARCHAR(100),
    contact_email       VARCHAR(150),
    contact_phone       VARCHAR(20),
    address_line1       VARCHAR(200),
    city                VARCHAR(60),
    state               VARCHAR(60),
    postal_code         VARCHAR(12),
    country             VARCHAR(60),
    currency            CHAR(3)         NOT NULL,
    total_amount        DECIMAL(14,2)   NOT NULL,
    line_count          INT             NOT NULL,
    order_status        VARCHAR(25)     NOT NULL,
    file_name           VARCHAR(200),
    sf_update_status    VARCHAR(20),
    email_status        VARCHAR(20),
    sf_last_modified    TIMESTAMP       NOT NULL,
    correlation_id      VARCHAR(50)     NOT NULL,
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP,
    CONSTRAINT uq_order_opportunity UNIQUE (opportunity_id)
);

-- 3. Create Lines Table: sales_order_line
CREATE TABLE IF NOT EXISTS sales_order_line (
    line_seq            SERIAL          PRIMARY KEY,
    order_number        VARCHAR(30)     NOT NULL,
    line_number         INT             NOT NULL,
    product_code        VARCHAR(30)     NOT NULL,
    product_name        VARCHAR(150),
    quantity            DECIMAL(10,2)   NOT NULL,
    unit_price          DECIMAL(12,2)   NOT NULL,
    line_total          DECIMAL(14,2)   NOT NULL,
    CONSTRAINT fk_line_order FOREIGN KEY (order_number)
        REFERENCES sales_order (order_number)
        ON DELETE CASCADE
);

-- 4. Create Exceptions Table: order_exception
CREATE TABLE IF NOT EXISTS order_exception (
    exception_seq       SERIAL          PRIMARY KEY,
    opportunity_id      VARCHAR(18)     NOT NULL,
    order_number        VARCHAR(30),
    error_code          VARCHAR(60)     NOT NULL,
    error_message       VARCHAR(500),
    retry_count         INT             DEFAULT 0,
    sf_task_id          VARCHAR(18),
    correlation_id      VARCHAR(50)     NOT NULL,
    raised_at           TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- 5. Performance Indexes
CREATE INDEX IF NOT EXISTS idx_sales_order_opp ON sales_order (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_sales_order_status ON sales_order (order_status);
CREATE INDEX IF NOT EXISTS idx_sales_order_line_order ON sales_order_line (order_number);
CREATE INDEX IF NOT EXISTS idx_order_exception_opp ON order_exception (opportunity_id);
CREATE INDEX IF NOT EXISTS idx_order_exception_corr ON order_exception (correlation_id);

-- Verification Query
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
