# Antigravity Engineering Progress Log

## Project Overview
- **Repository Root:** `c:\Users\acer\Documents\studio-workspace\sf-listener`
- **Application 1:** `sf-listener` (root Mule application: event capture, VM queue consumer, orchestrator, file writer, notification, replay API)
- **Application 2:** `order-system-api` (standalone System API over PostgreSQL fulfilment database)
- **Current Branch:** `feature/order-fulfilment-hardening`

---

## Progress Summary

### Checkpoint 1: MUnit Diagnostics & Fix (`sf-listener`) — COMPLETED
- **Runtime Environment:** System shell default was JDK 21 (`Temurin-21.0.12.1+1`). Mule 4.12 runtime extension `ObjectStore` rejects Java 21 (`Supported versions are: [1.8, 11, 17]`). Resolved by targeting Eclipse Adoptium JDK 17 at `C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot`.
- **Configuration Property Resolution:** `sf-listener.xml` line 66 requires `${secure.key}`. Updated root `pom.xml` to bridge `<secure.key>${env.SECURE_KEY}</secure.key>` and pass `<argLine>-Dsecure.key=${secure.key}</argLine>` to MUnit plugin.
- **Verification:** Ran `mvn test` under JDK 17 with `$env:SECURE_KEY` set. **BUILD SUCCESS**, all 4 tests in `retry-attempt-flow-test.xml` passed (0 failures, 0 errors).

### Checkpoint 2: Order System API Configuration & Test Suite (`order-system-api`) — COMPLETED
- **Configuration & Templates:** Created `local.properties.example` for both projects to provide safe Git-trackable templates. Local development `local.properties` (gitignored) configured with `http.port=8082` and database connection to local PostgreSQL `orders_db`.
- **Database Schema Verification:** Confirmed local PostgreSQL `orders_db` on port 5432 has matching schemas for `sales_order`, `sales_order_line`, `order_exception`, and sequence `order_number_seq`.
- **MUnit Test Suite Created:** Created `order-system-api/src/test/munit/order-system-api-test.xml` covering:
  - `POST /order-numbers`: 201 sequence generation
  - `POST /orders`: 201 order creation
  - `POST /orders`: 400 validation error on missing/mismatched line items
  - `POST /orders`: 409 duplicate order key error
  - `GET /orders/{orderNumber}`: 200 order detail retrieval
  - `GET /orders/{orderNumber}`: 404 order not found
  - `PATCH /orders/{orderNumber}`: 200 order status and fulfilment file update
- **Bug Fixes in Implementation:**
  - Fixed `order-system-api.xml` duplicate key error handler to match `type="ANY"` when description contains `"duplicate key"`, properly returning HTTP 409 for unique constraint violations.
  - Fixed MUnit mock payload media type in `patch-order-success-test` to `application/java` to eliminate stream incompatibility exception.
- **Verification:** Ran `mvn test` in `order-system-api` under JDK 17. **BUILD SUCCESS**, all 7 tests passed (0 failures, 0 errors) with **67.31% application coverage**.

### Checkpoint 3: DataWeave Hardening — COMPLETED
- **File:** `sf-listener/src/main/resources/dwl/build-email-body.dwl`
- **Fix:** Added null-safe guards (`default ""`, non-empty filtering on address components) to prevent runtime `NullPointerException` during string concatenation if Salesforce account number or shipping address fields are null.

### Checkpoint 4: API Gateway Autodiscovery Configuration (Stage 2) — COMPLETED
- Configured `<api-gateway:autodiscovery>` in both `order-api.xml` and `order-system-api.xml` referencing `${api.id}` with fallback `api.id=0` for offline/MUnit execution.
- Added API policy application guidelines in documentation.

### Checkpoint 5: Operational Monitoring & Alerting (Stage 3) — COMPLETED
- Implemented PostgreSQL operational monitoring views `vw_order_exceptions_alert` and `vw_failed_orders_summary`.
- Added `/health` monitoring endpoint to `order-api.xml` returning JSON status (`UP`, `WARNING`, `DEGRADED`).
- Created PowerShell diagnostic tool `scripts/monitor-health-alerts.ps1`.
- Added 3 MUnit tests in `monitoring-health-test.xml` (UP, WARNING, 503 DEGRADED).

### Checkpoint 6: Soak Test Harness & 30-Second SLA Benchmark (Stage 4) — COMPLETED
- Created `scripts/soak-test-benchmark.ps1` exercising the full sequence generation, canonical JSON payload building, transactional database insertion, atomic file generation, and status patching pipeline.
- Executed 200 orders across 60 seconds with 8 parallel workers:
  - **Orders Completed:** 200 / 200 (100% success rate, 0 errors).
  - **Throughput:** 188.1 orders/min (~200 opps/min target).
  - **Latency Profile:** Min: 217ms, Avg: 552.3ms, P95: 1,640ms, Max: 2,728ms.
  - **30-Second SLA Compliance:** 100% (all 200 orders completed in < 2.73 seconds, well within the 30-second ceiling).
  - **Layer 2 Idempotency:** Duplicate submission rejected with HTTP 409 Conflict.

---

| Task / Priority | Status | Details |
|---|---|---|
| **Priority 1: MUnit Deployment Error Fix (`sf-listener`)** | **DONE** | Fixed Java 21 incompatibility via JDK 17. Configured `${env.SECURE_KEY}` forwarding in `pom.xml`. 4/4 tests pass (BUILD SUCCESS). |
| **Priority 2: Inbound Consumer MUnit Coverage (`sf-listener`)** | **DONE** | Created `order-consumer-flow-test.xml`. 6/6 tests pass (happy path, amount mismatch, missing reference data, retry exhaustion, DLQ forwarding, invalid payload). |
| **Priority 3: Order System API Hardening (`order-system-api`)** | **DONE** | Created tracked property examples, verified PostgreSQL schema, fixed 409 duplicate key handler. 7/7 MUnit tests pass with 67.31% coverage (BUILD SUCCESS). |
| **Priority 4: Replay API & RAML Router (`sf-listener`)** | **DONE** | Created `order-replay-api-test.xml`. 6/6 tests pass (force flag, duplicate skipping, GET order details, 404). |
| **Priority 5: Watermark & Resume Behavior** | **DONE** | Verified `startup-watermark-flow` and ObjectStore persistence with 3 tests in `watermark-flow-test.xml`. |
| **Priority 6: Reference Data Caching (TTL 60m)** | **DONE** | Implemented `Reference_Data_Store` in `sf-listener.xml` with TTL 60 min. Verified cache hit and miss retrieval. |
| **Priority 7: Database Migration Script & Views** | **DONE** | Created repeatable `sql/init_database.sql` covering sequence, tables, indexes, constraints, and operational views. |
| **Priority 8: API Autodiscovery & Policies** | **DONE** | Added autodiscovery tags to both APIKit mains; documented manual API Manager policy configuration. |
| **Priority 9: Operational Health & Monitoring** | **DONE** | Added `/health` endpoint, monitoring script `monitor-health-alerts.ps1`, and 3 MUnit tests in `monitoring-health-test.xml`. |
| **Priority 10: Soak Testing & SLA Benchmark** | **DONE** | Benchmark harness `soak-test-benchmark.ps1` sustained 188.1 opps/min with 100% 30-second SLA compliance (avg 552ms). |
| **Priority 11: CloudHub 2.0 / RTF Deployment Profiles** | **DONE** | Implemented `cloudhub2`, `rtf`, and `cloudhub` profiles in both POMs; zero hardcoded secrets; validated via `mvn validate` and 29/29 MUnit PASS. |
| **Live External Integrations & CloudHub 2.0 Deployment** | **VERIFIED LIVE** | Deployed `order-system-api` & `sf-listener` to CloudHub 2.0 US-East-2. Connected to live Neon PostgreSQL, live Salesforce Org, and live Mailtrap. Live E2E tests verified. |

---

## Final Baseline & Live CloudHub Verification
- **`order-system-api-anirvamn-2026`:** **APPLIED & RUNNING** (CloudHub 2.0 US-East-2)
  - Public Ingress: `https://order-system-api-anirvamn-2026-kt0z6z.5sc6y6-2.usa-e2.cloudhub.io`
  - Database: Neon PostgreSQL (`ep-quiet-glade-b49ezqfp.c-6.us-east-2.aws.neon.tech:5432/neondb`)
  - Endpoints Tested: `GET /console/` (200), `POST /api/order-numbers` (201), `POST /api/orders` (201), `PATCH /api/orders/{id}` (200), `GET /api/orders/{id}` (200)
- **`sf-listener-anirvamn-2026`:** **APPLIED & RUNNING** (CloudHub 2.0 US-East-2)
  - Public Ingress: `https://sf-listener-anirvamn-2026-kt0z6z.5sc6y6-1.usa-e2.cloudhub.io`
  - Replicas: 1 / 1 STARTED (Green)
  - Endpoints Tested: `GET /console/` (200), `POST /api/orders/replay` (202 / 200), `GET /api/orders/{id}` (200)
- **Live End-to-End Golden Path Test:**
  - Opportunity: `006gK00000QFRYnQAP` (`Final Golden Path E2E 1791926336`, $55,000 USD)
  - Status in Salesforce: `Integration_Status__c = 'PROCESSED'`
  - ERP Number: `ERP_Order_Number__c = 'ERP-2026-000007'`
  - Message: `Integration_Message__c = 'Order created and file despatched'`
  - Fulfilment Timestamp: `Fulfilment_Date__c = '2026-10-13T21:19:12.000+0000'`
  - File Generated: `ORDER_ERP-2026-000007_20261014024912.xml`
  - Neon DB State: Header in `sales_order` & 2 items in `sales_order_line` (Total: $55,000.00)
- **Negative Scenarios Verified Live:**
  - Missing Reference Data: Opp `006gK00000QF9wrQAD` flagged `FAILED` (`Missing reference data: account ShippingCity is missing; account ShippingCountry is missing`)
  - Missing Line Items: Opp `006gK00000QFRbNQAX` flagged `FAILED` (`Opportunity has no line items, no order was created`)
  - Idempotency & Duplicate Prevention: Opp `006gK00000QFRYnQAP` replay returned `SKIPPED_DUPLICATE` (no duplicate DB row, no duplicate file)
- **MUnit Suite:** Total **29 / 29 Tests PASSING (100% Green, 0 Failures, 0 Errors)**
- **Git State:** Clean, zero secrets staged/tracked.


