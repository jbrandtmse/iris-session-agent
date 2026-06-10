# Reference: `HS.*` HealthShare Message Body Tables

Standard InterSystems **HealthShare** message-body classes you'll commonly join to from
`Ens.MessageHeader` in a healthcare-interoperability production. The class names, SAML
structure, stream handling, and collection-table mechanics below are HealthShare-standard.
Column lists are representative — confirm against `INFORMATION_SCHEMA` (`04`) — but the
**encodings and gotchas are the reusable knowledge**.

> Routing topology (which component sends to which, what the components are named) is entirely
> deployment-specific. This file uses placeholders like `'...Services'`, `'...Query.Process'`,
> `'...Operations'`, `'...Router'`. **Discover the real component names live** (`04`) — don't
> assume them. The *patterns* (which leg carries SAML, where data is empty) generalize; the
> *names* do not.

These classes recur across IHE profiles: **XCPD** (Cross-Gateway Patient Discovery),
**XCA**/**XDSb** (document query & retrieve), and FHIR. Those are public IHE/HL7 profile names,
useful only as context for what each body represents.

---

# `HS.Message.PatientSearchRequest` (SQL: `HS_Message.PatientSearchRequest`)

The patient-demographics search request body (IHE XCPD and FHIR patient flows). Wide table
(~130 columns); the ones that matter:

| Column | Type | Notes |
|--------|------|-------|
| `%ID` / `ID` | bigint | RowID. |
| `FirstName`, `LastName`, `DOB` (date), `MRN`, `MPIID`, `SSN`, `Sex` | various | Patient demographics being searched on. |
| `SAMLData_OrganizationID` | varchar | Source org identifier/OID (from the SAML assertion). |
| `SAMLData_Organization` | varchar | Source org name. |
| `SAMLData_OrganizationOID` | varchar | Source org OID. |
| `SAMLData_NPI`, `SAMLData_UserName`, `SAMLData_Subject`, `SAMLData_Issuer`, `SAMLData_PurposeOfUse` (integer) | various | ~19 `SAMLData_*` columns total. `PurposeOfUse` here is **integer-coded**. |
| `Facility` | varchar | Target org — **may be a friendly alias, not always an OID** (see resolution note below). |
| `RequestingGateway`, `SearchMode` | varchar | |
| `Type` | **varchar** | Note: a varchar here, unlike `Ens.MessageHeader.Type` (integer). Don't carry the integer assumption across tables. |

Also has embedded-object columns (`BirthPlace_*`, `FathersName_*`, `MothersName_*`,
`SpousesName_*`) and a `_CustomAuditInfo` collection table.

## `HS_Message.PatientSearchRequest_AdditionalInfo`

Key-value collection table (pivot pattern — see `02`). FK column is `PatientSearchRequest`;
value column is `AdditionalInfo`; key column is `element_key`. Commonly-seen keys (deployment-
dependent — **enumerate them live**):

| `element_key` | Meaning |
|---------------|---------|
| `WSA:To` / `WSA:From` / `WSA:MessageID` | WS-Addressing endpoint URLs / message UUID. |
| `PurposeOfUse` / `Purpose` | Exchange purpose (string here, vs the integer `SAMLData_PurposeOfUse` column). |
| `SOAPAction` | SOAP action URN. |
| `Network`, `GatewayType` | App routing hints (e.g. initiating vs responding gateway). |
| `RecOrgName` / `RecOrgOID` | **Target** org name / **OID** — the canonical target OID. |
| `SAMLOrganization` / `SAMLOrganizationOID` | Source org name / OID — populated on some flows where the `SAMLData_*` *columns* are empty (see below). |
| `Host`, `Port`, `URL` | Target connection parts. |

```sql
LEFT JOIN HS_Message.PatientSearchRequest_AdditionalInfo ai
  ON psr.%ID = ai.PatientSearchRequest AND ai.element_key = 'RecOrgOID'
```

## Patterns & gotchas (these generalize)

- **Source-org data location is flow-dependent.** On some flows the `SAMLData_Organization` /
  `SAMLData_OrganizationID` **columns** carry the source org; on others those columns are
  **empty** and the value lives in the `AdditionalInfo` keys `SAMLOrganization` /
  `SAMLOrganizationOID` instead. Check both, prefer whichever is populated for your flow.
- **On responding/inbound (host) namespaces, the PSR body's `SAMLData_*` columns are typically
  EMPTY** — the request arrived as a raw SOAP envelope first. Get the source org from the
  **inbound `HS.Message.XMLMessage`** body on the first leg of the session instead (see below).
- **First-PSR-in-session carries the source-org info.** When a session has several PSR rows
  (routing chain), the earliest (`MIN(ID)`) PSR usually carries `SAMLOrganizationOID` in
  `AdditionalInfo` regardless of its target. Use a `MIN(ID)` subquery to pick it and avoid
  duplicates:
  ```sql
  INNER JOIN Ens.MessageHeader psrh
    ON psrh.ID = ( SELECT MIN(h2.ID) FROM Ens.MessageHeader h2
                   WHERE h2.SessionId = hdr.SessionId
                     AND h2.MessageBodyClassName = 'HS.Message.PatientSearchRequest' )
  INNER JOIN HS_Message.PatientSearchRequest psr ON psrh.MessageBodyId = psr.%ID
  ```
- **Target identity: resolve off `RecOrgOID`, fall back to `Facility`.** `Facility` may be a
  friendly alias that won't join to a directory of OIDs; the canonical OID is the `RecOrgOID`
  AdditionalInfo key. Resolving off only `Facility` (or excluding a specific OID via `Facility`)
  misses rows where `Facility` holds the alias form:
  ```sql
  COALESCE(
    (SELECT TOP 1 r.AdditionalInfo FROM HS_Message.PatientSearchRequest_AdditionalInfo r
       WHERE r.PatientSearchRequest = psr.ID AND r.element_key = 'RecOrgOID'),
    psr.Facility) AS TargetOID
  ```
  (Use `TOP 1` — `RecOrgOID` can appear once per routing step.)
- **`PurposeOfUse` value formats differ by deployment/network** — don't hardcode a single
  literal; discover the actual values.
- **`SAMLData_OrganizationID` may carry a `urn:oid:` prefix** (sometimes uppercase). Strip it
  before joining to an OID directory: `REPLACE(REPLACE(col, 'URN:OID:', ''), 'urn:oid:', '')`.
- **Two collection tables can share a base name** — if both `HS_Message.PatientSearchRequest_AdditionalInfo`
  and an app's own `..._AdditionalInfo` exist, they are not interchangeable (different keys
  present). Verify which one has the data you need.
- **Error rate:** correlate to the response header (`IsError` lives there — `02`). On XCPD
  initiating legs `CorrespondingMessageId` is often populated (use it); on responding legs it's
  often `0` (self-join on SessionId + swapped configs instead).
- Use `%EXACT()` on endpoint URLs/OIDs in SELECT and GROUP BY to preserve case.

---

# `HS.Message.XMLMessage` (SQL: `HS_Message.XMLMessage`)

A generic SOAP/XML message body — used as request and/or response body for XCA query/retrieve
and as the raw inbound envelope on responding gateways. ~25 columns.

| Column | Type | Notes |
|--------|------|-------|
| `%ID` / `ID` | bigint | |
| `ContentStream` | **longvarchar (stream)** | The XML payload. Read with `SUBSTRING(ContentStream, 1, N)` (not `SUBSTR`/`CONVERT`). |
| `DocType`, `Name` | varchar | |
| `SOAPFault` | varbinary | |
| `StreamCollection` | varchar | |
| `SAMLData_Organization` | varchar | Source org **name** — the reliable source-org field on inbound responding legs. |
| `SAMLData_OrganizationID` | varchar | Source org OID — **may have `urn:oid:` prefix**. |
| `SAMLData_PurposeOfUse` | integer | Integer-coded (not the readable string). |
| `SAMLData_SAMLInfo` | varchar | A **nested `$LIST`** of `$LIST(key,value)` pairs — see extraction below. |
| ~18 more `SAMLData_*` | various | `Issuer`, `NPI`, `UserName`, `Subject`, `RHIO`, `Token`, `HSRoles`, `IDType`, etc. |

## `SAMLData_SAMLInfo` — nested `$LIST` extraction

It is **not** a delimited string — it's a `$LIST` whose elements are themselves `$LIST(key,
value)` pairs. Extract with nested `$LISTGET` (`$LISTFROMSTRING` does **not** apply):

```sql
$LISTGET($LISTGET(xml.SAMLData_SAMLInfo, N), 1) AS Key_at_N,
$LISTGET($LISTGET(xml.SAMLData_SAMLInfo, N), 2) AS Value_at_N
```

Observed (deployment-dependent) layout: position 1 = `PurposeOfUse` (value like `TREATMENT`/
`REQUEST`), 2 = a serialized purpose object, 3 = a source HCID/OID (bare), 4 = user name. When
the dedicated `SAMLData_PurposeOfUse` column is empty for a flow, pull purpose from this
`$LIST` instead.

## Patterns & gotchas

- **`ContentStream` is a stream:** `SUBSTRING(col, 1, N)` to read; `SUBSTR` errors (`SQLCODE
  -37`); `CONVERT(VARCHAR(N), col)` works but can time out on unfiltered queries.
- **Inbound vs response / fan-out legs:** the SAML data is on the **inbound** XMLMessage (the
  `.Services` → `.Query.Process`-style first leg, `Type=1`). The **response** XMLMessage (same
  route reversed, `Type=2`) and downstream **fan-out** legs (to `.Operations`) typically have
  **empty SAML**. To get source org for a downstream/fan-out row, join back through `SessionId`
  to the inbound XMLMessage:
  ```sql
  INNER JOIN Ens.MessageHeader xmlhdr
    ON xmlhdr.SessionId = fsh.SessionId
   AND xmlhdr.SourceConfigName = fsh.SourceConfigName
   AND xmlhdr.MessageBodyClassName = 'HS.Message.XMLMessage'
   AND xmlhdr.Type = 1
  INNER JOIN HS_Message.XMLMessage xml ON xmlhdr.MessageBodyId = xml.%ID
  -- xml.SAMLData_Organization = requesting org name; xml.SAMLData_OrganizationID = OID
  ```
- **Multiple inbound XMLMessages per session are possible** (e.g. one to a trace operation with
  the wrong purpose, one to the real recipient with the right purpose). Discriminate by
  `TargetConfigName` to pick the correct one.
- **Strip `urn:oid:`** from `SAMLData_OrganizationID` before joining to an OID directory.
- **Document counting from a response stream** — count XDS.b `</rim:ExtrinsicObject>` closing
  tags (22 chars each) in the content:
  ```sql
  (CHAR_LENGTH(SUBSTRING(xml.ContentStream, 1, 100000))
    - CHAR_LENGTH(REPLACE(SUBSTRING(xml.ContentStream, 1, 100000),
        '</rim:ExtrinsicObject>', ''))) / 22 AS Doc_Count
  ```

---

# `HS.Message.IHE.XDSb.QueryResponse` (SQL: `HS_Message_IHE_XDSb.QueryResponse`)

The XDS.b registry query **response** body — an IHE AdhocQueryResponse. ~34 columns; key ones:

| Column | Type | Notes |
|--------|------|-------|
| `%ID` / `ID` | bigint | |
| `ContentStream` | **longvarchar (stream)** | The `<rim:RegistryObjectList>` XML; each document is a `<rim:ExtrinsicObject>`. Empty responses use self-closing `<rim:RegistryObjectList/>`. |
| `Documents`, `Submissions`, `Folders`, `Associations`, `ObjectRefs`, `StreamCollection` | varchar | |
| `Errors_Errors`, `Errors_HighestError` | varchar | Response-level error info. |
| `HSMinVersionError` (bit), `HSCoreVersion`, `DocType`, `Name`, `SOAPFault` (varbinary) | various | Plus ~19 `SAMLData_*` columns (same pattern as other HS bodies). |

## Patterns & gotchas

- **Document count** (per message) — same `</rim:ExtrinsicObject>`/22 trick as above.
- **Multiple QueryResponse rows per session** (one per responding source/gateway). To total
  documents across a session, **sum** the per-message counts via a correlated subquery:
  ```sql
  (SELECT SUM(
       (CHAR_LENGTH(SUBSTRING(qr.ContentStream,1,100000))
         - CHAR_LENGTH(REPLACE(SUBSTRING(qr.ContentStream,1,100000),'</rim:ExtrinsicObject>','')))/22 )
     FROM Ens.MessageHeader qrh
     INNER JOIN HS_Message_IHE_XDSb.QueryResponse qr ON qrh.MessageBodyId = qr.%ID
     WHERE qrh.SessionId = hdr.SessionId
       AND qrh.MessageBodyClassName = 'HS.Message.IHE.XDSb.QueryResponse'
       AND qrh.TargetConfigName = 'MyApp.XCA.Query.Process'  -- the dedupe leg (discover real name)
  ) AS Doc_Count
  ```
- `ContentStream` is a stream — `SUBSTRING`, never `SUBSTR`.
- High-volume table — **always** apply a time constraint.

---

# `HS.FHIRServer.Interop.Request` (SQL: `HS_FHIRServer_Interop.Request`)

The FHIR-server interop request body (FHIR flows). ~29 columns; key ones:

| Column | Type | Notes |
|--------|------|-------|
| `%ID` / `ID` | bigint | |
| `Request_RequestMethod` | varchar | `GET`, `POST`, ... |
| `Request_RequestPath` | varchar | e.g. `DocumentReference/{id}`. |
| `Request_QueryString` | varchar | e.g. filter by `Request_QueryString LIKE 'patient=%'`. |
| `Request_Interaction`, `Request_Type`, `Request_BaseURL`, `Request_TimestampUTC` | various | |
| `Request_AdditionalInfo` | varchar | A **serialized nested `$LIST`** of `$LB($LB(key,val),...)` — HTTP headers + SAML data. See extraction. |
| (~19 more) | | `Request_SessionId`, `Request_SessionApplication`, `Request_Prefer`, `Request_IfMatch`, `Request_IfNoneMatch`, `QuickStreamId`, ... |

## `Request_AdditionalInfo` — positional nested `$LIST` (no usable collection table)

This is a **serialized `$LIST`**, *not* a relational collection — it cannot be JOINed, and the
similarly-named relational collection tables in a *different* FHIR schema (`HS_Message_FHIR.Request_*`)
do **not** FK to this class (they belong to a separate persistent class whose RowID is `ID1`).
So you must extract from the `$LIST` directly with nested `$LISTGET`.

**The key's position is not stable across rows** (extra HTTP headers shift it). Scan a *range*
of positions with a `CASE` that checks the key at each position. A scan across positions ~6–12
reliably found a header-borne org OID across tens of thousands of rows:

```sql
CASE
  WHEN $LISTGET($LISTGET(body.Request_AdditionalInfo, 6),  1) = 'HEADER:SOURCE_ORGANIZATION_OID'
    THEN $LISTGET($LISTGET(body.Request_AdditionalInfo, 6),  2)
  WHEN $LISTGET($LISTGET(body.Request_AdditionalInfo, 7),  1) = 'HEADER:SOURCE_ORGANIZATION_OID'
    THEN $LISTGET($LISTGET(body.Request_AdditionalInfo, 7),  2)
  -- ... repeat for positions 8, 9, 10, 11, 12 ...
  ELSE NULL
END AS SourceOrgOID
```

- Keys are `KIND:NAME` style (`USER:UserID`, `HEADER:X-Request-Id`, `HEADER:Accept`, etc.). A
  source-org *name* header may exist but be present on only a tiny fraction of rows — don't rely
  on it; the OID header is more consistent.
- **Universal across flow types** (GET/POST, document/patient/endpoint) — no auxiliary join
  needed when you only need the OID. (If you need *other* fields, a related PSR in the session
  may carry them — see the `MIN(ID)` PSR pattern above.)
- **Cost:** nested `$LISTGET` `CASE` scans across many positions × many rows are CPU-heavy. A
  ~7-day window may take a minute or two; a ~30-day window can time out — **aggregate weekly and
  combine** for longer ranges. Bound the time window aggressively.
- **Shell-escape `$LISTGET` as `\$LISTGET`** if passing the SQL through a shell.

## Deduping FHIR request legs

A FHIR session commonly has **two** request headers sharing the same body — an inbound leg
(`Router → Service`) and a routed leg (`Router → process`). Filter to the routed leg
(`SourceConfigName = '<the router>'`, discovered live) to avoid duplicate rows in aggregates.

## Aggregation: pivot by org + request type

Because IRIS can't reference aliases in `GROUP BY`, compute the bucketing in a subquery and
group outside (full pattern in `07`):

```sql
SELECT TOP 100 t.OrgOID,
  SUM(CASE WHEN t.RequestType = 'Patient POST' THEN 1 ELSE 0 END) AS PatPOST,
  SUM(CASE WHEN t.RequestType = 'DocRef GET'   THEN 1 ELSE 0 END) AS DocGET,
  COUNT(*) AS Total
FROM (
  SELECT
    CASE ... END AS OrgOID,        -- the position-scan above
    CASE
      WHEN rqh.TargetConfigName LIKE '%Patient.POST'        THEN 'Patient POST'
      WHEN rqh.TargetConfigName LIKE '%DocumentReference.GET'
        AND body.Request_QueryString LIKE 'patient=%'       THEN 'DocRef GET (patient)'
      WHEN rqh.TargetConfigName LIKE '%DocumentReference.GET' THEN 'DocRef GET (direct)'
      ELSE rqh.TargetConfigName
    END AS RequestType
  FROM Ens.MessageHeader rqh
  INNER JOIN HS_FHIRServer_Interop.Request body ON rqh.MessageBodyId = body.%ID
  WHERE rqh.MessageBodyClassName = 'HS.FHIRServer.Interop.Request'
    AND rqh.SourceConfigName = 'MyApp.FHIRRouter'   -- the routed leg (discover real name)
    AND rqh.TimeCreated > DATEADD('day', -7, CURRENT_TIMESTAMP)
) t
GROUP BY t.OrgOID
ORDER BY Total DESC
```
