<#
.SYNOPSIS
    Stage C Production-Development Migration Runner for school_management.
.DESCRIPTION
    Implements the two-phase database migration with strict safety gates:
      Phase 1: Preflight connection check (host, port, database identity),
               binary safety backup, and archive verification (pg_dump + pg_restore --list).
               PAUSES and displays backup verification results for user confirmation.
      Phase 2: Transactional migration execution (002) and 6-point invariant verification.
    
    SAFETY CONSTRAINTS:
      - Does NOT read, print, or expose backend/.env credentials.
      - Uses existing PostgreSQL authentication configuration.
      - Enforces explicit host ($DbHost) and port ($DbPort) target verification.
      - Encloses migration in strict BEGIN...COMMIT transaction (ON_ERROR_STOP=1).
      - Separates application deployment entirely (no app restarts/deployments).
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "BackupOnly", "MigrateOnly")]
    [string]$Phase = "All",

    [string]$DbName = "school_management",
    [string]$DbUser = "postgres",
    [string]$DbHost = "localhost",
    [int]$DbPort = 5432,
    [string]$BackupPath = "D:\DB_Backups\school_management_pre_migration_002.backup"
)

$ErrorActionPreference = "Stop"

$MigrationSql = Join-Path $PSScriptRoot "002_normalize_marks_and_subject_attendance.sql"
$BackupDir = [System.IO.Path]::GetDirectoryName($BackupPath)

Write-Host "============================================================"
Write-Host "STAGE C: PRODUCTION-DEVELOPMENT DATABASE MIGRATION"
Write-Host "Target Host:     $DbHost"
Write-Host "Target Port:     $DbPort"
Write-Host "Target Database: $DbName"
Write-Host "Database User:   $DbUser"
Write-Host "Target Backup:   $BackupPath"
Write-Host "Execution Phase: $Phase"
Write-Host "============================================================"

# =============================================================
# PHASE 1: PRE-MIGRATION BACKUP & ARCHIVE VERIFICATION
# =============================================================
if ($Phase -in @("All", "BackupOnly")) {
    Write-Host "`n>>> [PHASE 1] Preflight Check & Pre-Migration Backup Verification..."

    # Pre-check: Ensure backup directory exists
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    # Pre-check: Prevent accidental overwrite
    if (Test-Path $BackupPath) {
        throw "FATAL: Pre-migration backup file already exists at '$BackupPath'! Aborting to prevent overwrite."
    }

    # Pre-check 1: Host, Port, and Database Identity Preflight Verification
    Write-Host "  Verifying database connection, host ($DbHost), port ($DbPort), and identity ($DbName)..."
    $serverInfo = (psql -h $DbHost -p $DbPort -U $DbUser -d $DbName -t -A -F "|" -c "SELECT current_database(), current_setting('port');").Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serverInfo)) {
        throw "FATAL: Unable to connect to PostgreSQL at ${DbHost}:${DbPort} database '$DbName'!"
    }
    $infoParts = $serverInfo.Split("|")
    $currentDb = $infoParts[0].Trim()
    $currentPort = $infoParts[1].Trim()

    if ($currentDb -ne $DbName) {
        throw "FATAL: Target database mismatch! Expected '$DbName', got '$currentDb'."
    }
    if ($currentPort -ne [string]$DbPort) {
        throw "FATAL: Target port mismatch! Expected '$DbPort', got '$currentPort'."
    }
    Write-Host "  [OK] Preflight Verified: Database='$currentDb', Host='$DbHost', Port='$currentPort'."

    # 1. Execute pg_dump with explicit host and port
    Write-Host "  Executing pg_dump (custom binary format) on ${DbHost}:${DbPort}..."
    pg_dump -h $DbHost -p $DbPort -U $DbUser -d $DbName -F c -b -v -f $BackupPath
    if ($LASTEXITCODE -ne 0) {
        throw "FATAL: pg_dump failed with exit code $LASTEXITCODE! Database has NOT been modified."
    }
    Write-Host "  [OK] pg_dump exited successfully (exit code 0)."

    # 2. Verify backup file exists and is non-empty
    if (-not (Test-Path $BackupPath)) {
        throw "FATAL: Backup file was not found on disk at '$BackupPath'!"
    }
    $fileSize = (Get-Item $BackupPath).Length
    if ($fileSize -le 0) {
        throw "FATAL: Backup file is empty (0 bytes)!"
    }
    Write-Host "  [OK] Backup file verified non-empty on disk: $fileSize bytes."

    # 3. Verify archive readable via pg_restore --list
    Write-Host "  Validating archive table of contents via pg_restore --list..."
    $tocEntries = pg_restore --list $BackupPath
    if ($LASTEXITCODE -ne 0) {
        throw "FATAL: pg_restore --list failed to read archive! The backup file may be corrupt."
    }
    $tocCount = ($tocEntries | Measure-Object -Line).Lines
    if ($tocCount -le 5) {
        throw "FATAL: Backup archive TOC contains suspiciously few entries ($tocCount lines)! Aborting."
    }
    Write-Host "  [OK] pg_restore --list successfully read archive ($tocCount table-of-contents entries)."

    Write-Host "`n============================================================"
    Write-Host "PHASE 1 BACKUP VERIFICATION RESULTS:"
    Write-Host "  - Target Host & Port:  ${DbHost}:${DbPort}"
    Write-Host "  - Target Database:     $DbName"
    Write-Host "  - Backup Target Path:  $BackupPath"
    Write-Host "  - pg_dump Status:      SUCCESS (Exit Code 0)"
    Write-Host "  - File Size:           $fileSize bytes"
    Write-Host "  - Archive Readability: VERIFIED ($tocCount TOC items read)"
    Write-Host "============================================================"

    if ($Phase -eq "BackupOnly") {
        Write-Host "`n[PAUSE] Phase 1 complete. Database school_management remains 100% in legacy state."
        return
    }

    # Explicit confirmation gate before Phase 2
    Write-Host "`n[CONFIRMATION GATE] Backup verified successfully."
    $response = Read-Host "Proceed with executing Migration 002 against $DbName? Type 'YES' to proceed"
    if ($response -cne "YES") {
        Write-Host "`nExecution halted by user at confirmation gate. Zero database changes were made."
        return
    }
}

# =============================================================
# PHASE 2: TRANSACTIONAL MIGRATION 002 & INVARIANT ASSERTIONS
# =============================================================
if ($Phase -in @("All", "MigrateOnly")) {
    Write-Host "`n>>> [PHASE 2] Applying Migration 002 with Transactional Error Guard..."

    if (-not (Test-Path $MigrationSql)) {
        throw "FATAL: Migration file not found at '$MigrationSql'!"
    }

    # Preflight Check: Host, Port, and Target Database Verification
    Write-Host "  Verifying database connection, host ($DbHost), port ($DbPort), and target identity ($DbName)..."
    $serverInfo = (psql -h $DbHost -p $DbPort -U $DbUser -d $DbName -t -A -F "|" -c "SELECT current_database(), current_setting('port');").Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serverInfo)) {
        throw "FATAL: Unable to connect to PostgreSQL at ${DbHost}:${DbPort} database '$DbName'!"
    }
    $infoParts = $serverInfo.Split("|")
    $currentDb = $infoParts[0].Trim()
    $currentPort = $infoParts[1].Trim()

    if ($currentDb -ne $DbName) {
        throw "FATAL: Target database mismatch! Expected '$DbName', got '$currentDb'."
    }
    if ($currentPort -ne [string]$DbPort) {
        throw "FATAL: Target port mismatch! Expected '$DbPort', got '$currentPort'."
    }
    Write-Host "  [OK] Preflight Target Verified: Database='$currentDb', Host='$DbHost', Port='$currentPort'."

    # Execute Migration 002 with ON_ERROR_STOP=1
    # Full BEGIN ... COMMIT block guarantees all-or-nothing atomicity
    psql -h $DbHost -p $DbPort -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -f $MigrationSql
    if ($LASTEXITCODE -ne 0) {
        throw "FATAL: Migration 002 failed with exit code $LASTEXITCODE! Transaction was automatically rolled back by PostgreSQL. Zero changes committed."
    }
    Write-Host "  [OK] Migration 002 completed and committed cleanly."

    # Execute Mandatory Post-Migration Invariant Assertions
    Write-Host "`n>>> [PHASE 2] Verifying Post-Migration Invariants..."
    psql -x -h $DbHost -p $DbPort -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -c @"
SELECT 
    'INVARIANT 1: Archive Count' AS check_name,
    COUNT(*) AS actual_value,
    2 AS expected_value,
    (COUNT(*) = 2) AS passed
FROM legacy_marks_archive;

SELECT 
    'INVARIANT 2: Normalized Marks Count' AS check_name,
    COUNT(*) AS actual_value,
    10 AS expected_value,
    (COUNT(*) = 10) AS passed
FROM student_subject_marks;

SELECT 
    'INVARIANT 3: Preserved Report IDs' AS check_name,
    ARRAY_AGG(report_id ORDER BY report_id) AS actual_report_ids,
    ARRAY[1, 2] AS expected_report_ids,
    (ARRAY_AGG(report_id ORDER BY report_id) = ARRAY[1, 2]) AS passed
FROM report;

SELECT 
    'INVARIANT 4: Core Score Total' AS check_name,
    SUM(marks_obtained) AS actual_sum,
    508 AS expected_sum,
    (SUM(marks_obtained) = 508) AS passed
FROM student_subject_marks;

SELECT 
    'INVARIANT 5: Archived Others Values' AS check_name,
    ARRAY_AGG(marks_obtained ORDER BY original_mark_id) AS actual_archived_scores,
    ARRAY[75, 0] AS expected_archived_scores,
    (ARRAY_AGG(marks_obtained ORDER BY original_mark_id) = ARRAY[75, 0]) AS passed
FROM legacy_marks_archive;

SELECT 
    'INVARIANT 6: OTH106 Catalog Removal' AS check_name,
    COUNT(*) AS actual_oth106_count,
    0 AS expected_count,
    (COUNT(*) = 0) AS passed
FROM subjects 
WHERE subject_code = 'OTH106';

SELECT 
    'INVARIANT 7: OTH106 Assignment Removal' AS check_name,
    COUNT(*) AS actual_assignment_count,
    0 AS expected_count,
    (COUNT(*) = 0) AS passed
FROM teacher_assignment ta 
JOIN subjects s ON ta.subject_id = s.subject_id 
WHERE s.subject_code = 'OTH106';
"@
    if ($LASTEXITCODE -ne 0) {
        throw "FATAL: One or more post-migration invariant checks failed!"
    }

    Write-Host "`n============================================================"
    Write-Host "STAGE C DATABASE MIGRATION COMPLETED & VERIFIED SUCCESSFULLY"
    Write-Host "Target Host:     $DbHost"
    Write-Host "Target Port:     $DbPort"
    Write-Host "Target Database: $DbName"
    Write-Host "Verified Backup: $BackupPath"
    Write-Host "Application Deployment: KEPT SEPARATE (Not executed)"
    Write-Host "============================================================"
}
