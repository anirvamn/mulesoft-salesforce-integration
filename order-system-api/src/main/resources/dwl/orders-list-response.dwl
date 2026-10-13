%dw 2.0
output application/json
---
payload map (row) -> {
    orderNumber: row.order_number,
    opportunityId: row.opportunity_id,
    accountName: row.account_name,
    currency: row.currency,
    totalAmount: row.total_amount,
    lineCount: row.line_count,
    orderStatus: row.order_status,
    fileName: row.file_name,
    fileStatus: row.file_status,
    sfUpdateStatus: row.sf_update_status,
    emailStatus: row.email_status,
    correlationId: row.correlation_id,
    createdAt: row.created_at as String,
    updatedAt: row.updated_at as String
}