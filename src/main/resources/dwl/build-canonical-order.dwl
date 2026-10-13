   %dw 2.0
   output application/json
   var opp = vars.enriched[0]
   var lines = opp.OpportunityLineItems default []
   var contact = ((opp.OpportunityContactRoles default [])[0]).Contact
   var builtLines = lines map ((l, i) -> do {
       var qty = l.Quantity as Number
       var price = l.UnitPrice as Number
       ---
       {
         lineNumber: i + 1,
         productCode: l.Product2.ProductCode,
         productName: l.Product2.Name,
         quantity: qty,
         unitPrice: price,
         lineTotal: qty * price
       }
   })
   ---
   {
     orderNumber: vars.orderNumber,
     opportunityId: opp.Id,
     orderDate: (now() >> "Asia/Kolkata") as String {format: "yyyy-MM-dd'T'HH:mm:ssXXX"},
     account: {
       accountId: opp.AccountId,
       accountName: opp.Account.Name,
       accountNumber: opp.Account.AccountNumber,
       contactName: contact.Name,
       contactEmail: contact.Email,
       contactPhone: contact.Phone
     },
     shippingAddress: {
       addressLine1: opp.Account.ShippingStreet,
       city: opp.Account.ShippingCity,
       state: opp.Account.ShippingState,
       postalCode: opp.Account.ShippingPostalCode,
       country: opp.Account.ShippingCountry
     },
     currency: payload.payload.currency default "INR",
     lines: builtLines,
     lineCount: sizeOf(builtLines),
     totalAmount: sum(builtLines.lineTotal),
     orderStatus: "RECEIVED",
     correlationId: payload.correlationId
   }