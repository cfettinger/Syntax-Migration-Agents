---
name: postal-migration
description: Fixed-width Delstat parsing rules, Azure architecture constraints, and resume logic for the Postal VB.NET-to-.NET 8 migration.
---

# Postal Migration Skill

## Fixed-Width Parsing (309-byte records)
- Encoding: 7-bit ASCII, no BOM.
- Record type at byte 0:
  - `C` = copyright/volume → skip all such records.
  - `D` = detail → process.
- 0-based offsets. Key fields:
  - ZipCode: start 1, length 5
  - RouteID: start 17, length 4
  - actBCentral: start 21, length 5 (int)
  - (see full table in spec.md for remaining actB* / actR* fields)
- Trim ASCII spaces before int.Parse; treat non-numeric as malformed.
- Support both raw (no CR/LF) and CRLF-delimited files: sniff first chunk for `\r`/`\n`, rewind, then parse.
- Fail the job on records that are not exactly 309 bytes or have invalid type (except C).
- Source of truth: `trunk/Form1.vb` Substring calls.

## Azure Architecture Constraints
- Browser uploads directly to private Blob container via user-delegation SAS (Create + Write, ≤ 1 hour).
- File never touches App Service or temp disk.
- Worker (hosted service or Azure Function) streams blob → SqlBulkCopy into Delstat.
- Queue (`imports`) with single message per job; conditional Queued→Running update for lease.
- Managed identity for all access.
- Storage roles: Blob Data Contributor **and** Blob Delegator.
- SQL: INSERT on Delstat/ImportJob + EXECUTE on Postalweb and Postalwebboth only.
- Resume: skip already-accepted D records by RowsWritten count; truncate only when RowsWritten == 0.
- After final batch, execute Postalweb and Postalwebboth.
- Cap ~10 GB; log with jobId correlation in Application Insights.

## Status Tracking
Always update `Postal/status.md` in the Syntax-Migration-Agents repo (via the local path the user provides) after meaningful progress. Do not rely on the currently open solution for that file.
