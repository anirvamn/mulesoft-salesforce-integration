   %dw 2.0
   output application/json
   ---
   {
     correlationId: payload.correlationId default uuid(),
     eventType: "OPPORTUNITY_CLOSED_WON",
     eventTimestamp: now(),
     replayId: payload.replayId default null,
     retryCount: payload.retryCount default 0,
     payload: {
       opportunityId: payload.Id,
       accountId: payload.AccountId,
       ownerId: payload.OwnerId,
       amount: payload.Amount,
       currency: payload.CurrencyIsoCode default "INR",
       closeDate: payload.CloseDate,
       lastModifiedDate: payload.LastModifiedDate
     }
   }