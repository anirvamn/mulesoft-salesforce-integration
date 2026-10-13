%dw 2.0
output application/json
var h = vars.orderRows[0]
---
{
    orderNumber: h.order_number,
    opportunityId: h.opportunity_id,
    orderStatus: h.order_status,
    currency: h.currency,
    totalAmount: h.total_amount,
    lineCount: h.line_count,
    account: {
        accountId: h.account_id,
        accountName: h.account_name,
        accountNumber: h.account_number,
        contactName: h.contact_name,
        contactEmail: h.contact_email,
        contactPhone: h.contact_phone
    },
    shippingAddress: {
        addressLine1: h.address_line1,
        city: h.city,
        state: h.state,
        postalCode: h.postal_code,
        country: h.country
    },
    fileName: h.file_name,
    fileStatus: h.file_status,
    sfUpdateStatus: h.sf_update_status,
    emailStatus: h.email_status,
    correlationId: h.correlation_id,
    createdAt: h.created_at as String,
    updatedAt: h.updated_at as String,
    lines: vars.orderLines map (l) -> {
        lineNumber: l.line_number,
        productCode: l.product_code,
        productName: l.product_name,
        quantity: l.quantity,
        unitPrice: l.unit_price,
        lineTotal: l.line_total
    }
}