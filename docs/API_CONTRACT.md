# API contract the Flutter app expects (backend must implement)
Base: /api. Auth: `Authorization: Bearer <jwt>`. Errors: `{ "error": "message" }`.

| Method & path | Body / query | Response |
|---|---|---|
| POST /auth/register | name,email,password | { token, user:{name,email} } |
| POST /auth/login | email,password | { token, user:{name,email} } |
| GET /routes | origin=lat,lng & destination=text | { routes:[RouteOption] } |
| GET/POST /contacts, DELETE /contacts/:id | name,phone,consentToShare | { contacts:[...] } |
| POST /journeys | destination,routeId,expectedArrival,checkInMinutes,contactIds | { journey } |
| GET /journeys | | { journeys:[...] } |
| POST /journeys/:id/check-in, /complete, /cancel | | {} |
| GET/POST /reports | category,description,approximateLocation,location | { reports:[...] } |
| GET /notifications | | { notifications:[...] } |
| GET /places/safe-havens | lat,lng | { places:[{name,type,location:{lat,lng},distanceM,openNow?,hours?}] } |

RouteOption: id,label,durationMin,extraMin,distanceKm,riskLevel(low|moderate|high|unknown),confidenceLevel(low|medium|high),recommended,explanation,path:[{lat,lng}],segments:[SegmentAssessment].
SegmentAssessment = output of backend/src/services/safetyEngine.ts plus id,name.
