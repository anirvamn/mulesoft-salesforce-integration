   %dw 2.0
   output application/json
   ---
   {
     correlationId: uuid(),
     eventType: "OPPORTUNITY_CLOSED_WON",
     eventTimestamp: now(),
     replayId: null,
     retryCount: 0,
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