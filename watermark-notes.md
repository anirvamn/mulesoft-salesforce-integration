# Watermark behaviour (Checkpoint 8)

- After each accepted Closed Won event, the last LastModifiedDate is saved
  in the persistent Object Store "Watermark_Store" (key: lastProcessedModified).
- On startup, startup-watermark-flow reads it and logs "WATERMARK found" or
  "WATERMARK not found".
- If the watermark is lost (store deleted or corrupted): the app logs a WARN
  "starting fresh". Salesforce changes made while the app was down may be
  polled again. The duplicate check (Id|LastModifiedDate, 7-day TTL) skips
  events already processed, and the Integration_Status__c = PROCESSED filter
  skips completed opportunities. Events older than the duplicate TTL could be
  re-queued once, which is safe because the database has a unique constraint
  on opportunity_id (Checkpoint 10).
- Recovery: use the replay API (Checkpoint 19) for any missed opportunity.