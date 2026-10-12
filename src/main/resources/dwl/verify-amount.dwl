   %dw 2.0
   output application/json
   var opp = vars.enriched[0]
   var lines = opp.OpportunityLineItems default []
   var calculated = sum(lines map ((l) -> (l.Quantity as Number) * (l.UnitPrice as Number)))
   var amount = (opp.Amount default "0") as Number
   var tolerance = p("amount.tolerance") as Number
   ---
   {
     lineCount: sizeOf(lines),
     calculatedTotal: calculated,
     opportunityAmount: amount,
     difference: abs(calculated - amount),
     tolerance: tolerance,
     hasLines: sizeOf(lines) > 0,
     amountMatches: abs(calculated - amount) <= tolerance
   }