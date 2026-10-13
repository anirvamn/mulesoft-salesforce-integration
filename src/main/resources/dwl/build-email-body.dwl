%dw 2.0
output text/plain
var o = vars.canonicalOrder
var lineText = (o.lines map ((l) ->
    "  " ++ l.lineNumber ++ ". " ++ l.productName ++ " (" ++ l.productCode ++ ")\n" ++
    "     Quantity " ++ l.quantity ++ " at " ++ o.currency ++ " " ++ l.unitPrice ++ " = " ++ o.currency ++ " " ++ l.lineTotal
)) joinBy "\n"
---
"Hello Fulfilment Team,\n\n" ++
"A new order has been raised from a closed-won opportunity in Salesforce.\n\n" ++
"Order Number: " ++ o.orderNumber ++ "\n" ++
"Order Date: " ++ o.orderDate ++ "\n" ++
"Account: " ++ (o.account.accountName default "") ++ (if (o.account.accountNumber != null) (" (" ++ o.account.accountNumber ++ ")") else "") ++ "\n" ++
"Opportunity: " ++ (o.opportunityId default "") ++ "\n" ++
"Order Value: " ++ (o.currency default "") ++ " " ++ (o.totalAmount default 0) ++ "\n" ++
"Fulfilment File: " ++ (vars.finalFileName default "") ++ "\n" ++
"Ship To: " ++ (([o.shippingAddress.addressLine1, o.shippingAddress.city, o.shippingAddress.state, o.shippingAddress.postalCode, o.shippingAddress.country] filter (!isEmpty($))) joinBy ", ") ++ "\n\n" ++
"Line Items:\n" ++ lineText ++ "\n\n" ++
"Correlation Id: " ++ o.correlationId ++ "\n\n" ++
"Regards,\nOrder Fulfilment Service"