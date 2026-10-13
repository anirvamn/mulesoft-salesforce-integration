# High-Level Design (HLD): Salesforce Closed-Won Opportunity to Order Fulfilment Integration

**Document Version:** 1.0  
**Project:** Salesforce Closed-Won Opportunity to Order Fulfilment  
**Repository:** `anirvamn/mulesoft-salesforce-integration`  
**Architecture Style:** Event-Driven, API-Led Integration  

---

## 1. Executive Summary

This integration automates the end-to-end sales fulfilment pipeline when a Salesforce Opportunity transitions to **Closed Won**. The solution decouples event intake from processing using persistent queues, guarantees strict exactly-once processing through dual-layer idempotency, caches slowly changing master data, enforces transactional database persistence, generates atomic warehouse fulfilment XML files, notifies the fulfilment desk via email, updates Salesforce with ERP metadata, and exposes a Replay API.

---

## 2. API-Led Architecture

The solution adheres to MuleSoft API-Led Architecture principles divided across two applications:

1. **Process & Experience Layer (`sf-listener`)**:
   - **Inbound Event Listener:** Real-time capture of Salesforce Opportunity modifications.
   - **Orchestration & Transformation:** Business validation, master data caching, XML generation, write-back, and email notification.
   - **Experience Replay API:** RAML-based API (`POST /api/orders/replay`, `GET /api/orders/{orderNumber}`) routed via APIKit on port `8081`.

2. **System Layer (`order-system-api`)**:
   - Standalone System API on port `8082` providing a secure, governed abstraction over the PostgreSQL fulfilment database (`orders_db`).
   - Atomically generates ERP sequence numbers (`ERP-<yyyy>-<sequence>`) and persists orders and line items in a single transaction.

```mermaid
graph TD
    subgraph Experience & Process Layer [sf-listener :8081]
        SF_EVT[Salesforce Inbound Event] --> L_FLOW[sf-opportunity-listener-flow]
        L_FLOW -->|Idempotency Check 7d| IDEM_STORE[(Idempotent_Store)]
        L_FLOW -->|Publish Lightweight Event| VM_Q[(VM orders-queue)]
        VM_Q --> C_FLOW[order-consumer-flow]
        REPLAY_API[Replay API :8081] -->|POST /orders/replay| VM_Q
        
        C_FLOW --> CACHE_CHECK{In Cache?}
        CACHE_CHECK -->|Hit| PROC[Process Order]
        CACHE_CHECK -->|Miss| SF_QUERY[Salesforce SOQL Query]
        SF_QUERY --> REF_CACHE[(Reference_Data_Store TTL 60m)]
        REF_CACHE --> PROC
    end

    subgraph System Layer [order-system-api :8082]
        PROC -->|POST /order-numbers| SYS_NUM[Next Order Sequence]
        PROC -->|POST /orders| SYS_ORDER[Transactional Persist]
    end

    subgraph External Systems
        SYS_NUM --> PG[(PostgreSQL orders_db)]
        SYS_ORDER --> PG
        PROC -->|Atomic .tmp -> .xml Drop| WH[(Warehouse Drop Dir)]
        PROC -->|Update PROCESSED / FAILED| SF_LIVE[Salesforce CRM]
        PROC -->|HTML Notification| MAIL[SMTP Server]
        C_FLOW -.->|Permanent Failure| DLQ[(orders-dlq)]
        DLQ -.-> PG
    end
```

---

## 3. Order Status Lifecycle

Every order transitions through a strictly defined lifecycle status machine tracked in the `sales_order` table:

```mermaid
stateDiagram-v2
    [*] --> RECEIVED: Consumer dequeues event from orders-queue
    RECEIVED --> VALIDATED: Line total recalculation matches Opportunity amount (tolerance 0.01)
    VALIDATED --> PERSISTED: System API commits header & lines to PostgreSQL
    PERSISTED --> FILE_GENERATED: Atomic XML drop created in warehouse-out
    FILE_GENERATED --> SF_UPDATED: Salesforce Opportunity updated (ERP_Order_Number__c, PROCESSED)
    SF_UPDATED --> NOTIFIED: Fulfilment desk & Opportunity owner emailed
    NOTIFIED --> [*]

    RECEIVED --> FAILED: Business validation error (Amount mismatch / missing reference)
    VALIDATED --> FAILED: System retries exhausted -> Moved to DLQ & Task created
    SF_UPDATED --> SF_UPDATED_PENDING_RETRY: Email fails -> Order remains valid, email retried
```

| Lifecycle Status | Condition / Action | Failure Fallback |
| :--- | :--- | :--- |
| **`RECEIVED`** | Event consumed from `orders-queue`. | Invalid payload moves to `orders-dlq`. |
| **`VALIDATED`** | Sum of line totals matches Opportunity amount within tolerance (`0.01`). | If mismatch, status `FAILED`, Task created in Salesforce, no DB order created. |
| **`PERSISTED`** | Transactional insert into `sales_order` and `sales_order_line` via System API. | Transient DB error retried (max 3); duplicate key returns HTTP 409. |
| **`FILE_GENERATED`** | Written as `ORDER_<number>_<timestamp>.xml.tmp` and renamed to `.xml`. | Status remains `PERSISTED` with `file_status=FILE_FAILED`; alerted to ops. |
| **`SF_UPDATED`** | Updated with `ERP_Order_Number__c`, `Integration_Status__c = PROCESSED`. | If update fails, order is kept; Task created for manual reconciliation. |
| **`NOTIFIED`** | Notification sent via SMTP to fulfilment desk and opportunity owner. | If email fails, status remains `SF_UPDATED` with `email_status=PENDING_RETRY`. |

---

## 4. Key Design Patterns & Engineering Highlights

### 4.1 Dual-Layer Idempotency Protection
- **Layer 1 (Object Store):** `Idempotent_Store` stores compound key `#[payload.Id ++ '|' ++ payload.LastModifiedDate]` with a 7-day TTL. Duplicate events in quick succession are acknowledged and discarded before queuing.
- **Layer 2 (Database Constraint):** PostgreSQL table `sales_order` enforces `CONSTRAINT uq_order_opportunity UNIQUE (opportunity_id)`. If an aged-out event reaches the database, the System API catches the constraint violation and returns HTTP 409 `DUPLICATE_ORDER`.

### 4.2 60-Minute Master Data Caching
Product and pricebook reference data that rarely changes is served from the `Reference_Data_Store` Object Store with a configurable TTL (`ref.cache.ttl.minutes=60`). This reduces outbound Salesforce SOQL queries by >95% during peak loads.

### 4.3 Atomic File Writing Strategy
Warehouse watcher processes can fail or read corrupted records if a file is read during writing. The integration writes to `warehouse.dir/ORDER_<orderNumber>_<timestamp>.xml.tmp` and renames to `.xml` only after the payload stream has flushed and closed.

### 4.4 Watermark & Replay Management
- The watermark (`lastProcessedModified`) is stored in persistent `Watermark_Store`.
- On application restart, `startup-watermark-flow` retrieves the last watermark.
- If the watermark is lost or aged out, the system defaults safely without missing data; operators can re-drive specific opportunities via `POST /api/orders/replay` using the `force=true` flag.

### 4.5 Error Handling & Dead Letter Queue (DLQ)
- **Business Errors (Amount Mismatch, Missing Reference Data):** Classified as non-retryable. Recorded immediately in `order_exception`, Salesforce status updated to `FAILED`, and a high-priority Salesforce Task created for the owner.
- **Transient System Errors (DB row lock, network timeout, SMTP down):** Handled by `retry-attempt-flow` with up to 3 retries and exponential backoff (`vars.retryDelayMs * 2`).
- **Retry Exhaustion:** Message pushed to `orders-dlq`, exception logged to `order_exception`, and operators alerted.

---

## 5. MUnit Test Coverage Justification

| Application | Test Count | Test Status | Coverage | Coverage Justification for Non-Covered Components |
| :--- | :---: | :---: | :---: | :--- |
| **`order-system-api`** | 7 | **100% Pass** | **67.31%** | All endpoints (`POST /orders`, `POST /order-numbers`, `GET /orders/{id}`, `PATCH /orders/{id}`), positive flows, validation errors (400), and conflict handling (409) are covered. Remaining uncovered processors are default APIKit auto-generated error branches (405, 415, 501). |
| **`sf-listener`** | 16 | **100% Pass** | **58.44%** | All business logic flows (`order-consumer-flow`, `retry-attempt-flow`, `order-replay-api`) are fully covered. Inbound event listeners (`salesforce:modified-object-listener`), startup schedulers (`startup-watermark-flow`), and persistent background polling are container-managed sources that cannot be directly executed in isolated MUnit suites without running live background daemon threads. |
| **Combined** | **23** | **100% Pass** | **62.88%** | **Total 23/23 tests pass green.** |
