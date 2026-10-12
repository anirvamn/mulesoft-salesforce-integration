%dw 2.0
output application/json
var opp = vars.enriched[0]
var lines = opp.OpportunityLineItems default []
var missingProducts = (lines filter ((l) -> isEmpty(l.Product2.ProductCode default ""))) map ((l) -> "product code missing for line item " ++ (l.Id default "unknown"))
var missingAddress = ["ShippingStreet", "ShippingCity", "ShippingCountry"] filter ((f) -> isEmpty(opp.Account[f] default "")) map ((f) -> "account " ++ f ++ " is missing")
var missingPricebook = if (isEmpty(opp.Pricebook2Id default "")) ["opportunity has no pricebook"] else []
var missing = missingProducts ++ missingAddress ++ missingPricebook
---
{
  hasMissing: sizeOf(missing) > 0,
  missing: missing,
  message: missing joinBy "; "
}