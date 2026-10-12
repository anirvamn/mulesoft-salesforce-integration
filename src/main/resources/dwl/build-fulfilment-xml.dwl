%dw 2.0
output application/xml encoding="UTF-8"
var o = vars.canonicalOrder
---
FulfilmentOrder: {
  Header: {
    OrderNumber: o.orderNumber,
    OrderDate: o.orderDate,
    SourceSystem: "SALESFORCE",
    SourceRecordId: o.opportunityId,
    CorrelationId: o.correlationId,
    Customer: {
      AccountNumber: o.account.accountNumber,
      Name: o.account.accountName,
      ContactEmail: o.account.contactEmail
    },
    ShipTo: {
      AddressLine1: o.shippingAddress.addressLine1,
      City: o.shippingAddress.city,
      State: o.shippingAddress.state,
      PostalCode: o.shippingAddress.postalCode,
      Country: o.shippingAddress.country
    },
    Currency: o.currency,
    TotalAmount: o.totalAmount as String {format: "0.00"}
  },
  Lines: {
    (o.lines map ((l) -> {
      Line @(number: l.lineNumber): {
        ProductCode: l.productCode,
        Quantity: l.quantity as String {format: "0.##"},
        UnitPrice: l.unitPrice as String {format: "0.00"},
        LineTotal: l.lineTotal as String {format: "0.00"}
      }
    }))
  }
}