-- ============================================================
-- ROLLBACK SCRIPT FOR MIGRATION 002
-- Database: PostgreSQL (school_management / school_management_test / disposable test DB)
-- Safely reverses migration 002 with zero data loss for both historical
-- records and any new marks/attendance entered while migration 002 was active.
-- ============================================================

BEGIN;

-- ============================================================
-- STEP 1: RESTORE OTH106 SUBJECT IN CATALOG
-- ============================================================
INSERT INTO subjects (subject_code, subject_name, department)
VALUES ('OTH106', 'Others', 'General')
ON CONFLICT (subject_code) DO NOTHING;

-- ============================================================
-- STEP 2: RESTORE HISTORICAL 'OTHERS' SCORES IN LEGACY MARKS
-- Reads original scores from legacy_marks_archive (never replacing with 0)
-- Preserves Populated, Zero, and NULL values identically
-- ============================================================
UPDATE marks m
SET others = a.marks_obtained
FROM legacy_marks_archive a
WHERE m.mark_id = a.original_mark_id;

-- Explicit dependency check: Refuse to silently drop dependent objects with CASCADE
DO $$
DECLARE
    v_dependent_count INTEGER;
    v_dependents TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'student_reports' AND relkind = 'v') THEN
        SELECT COUNT(*), string_agg(dependent_view.relname, ', ')
        INTO v_dependent_count, v_dependents
        FROM pg_depend 
        JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid 
        JOIN pg_class AS dependent_view ON pg_rewrite.ev_class = dependent_view.oid 
        WHERE pg_depend.refobjid = 'student_reports'::regclass 
          AND dependent_view.oid != 'student_reports'::regclass;

        IF v_dependent_count > 0 THEN
            RAISE EXCEPTION 'ROLLBACK SAFETY HALT: Cannot drop student_reports view because % dependent object(s) rely on it: [%]. Refusing to silently drop dependent objects with CASCADE.',
                v_dependent_count, v_dependents;
        END IF;
    END IF;
END $$;

DROP VIEW IF EXISTS student_reports;

ALTER TABLE marks ALTER COLUMN exam_type TYPE VARCHAR(50);
ALTER TABLE report ALTER COLUMN exam_type TYPE VARCHAR(50);

-- ============================================================
-- STEP 4: COLLISION DETECTION & UNPIVOTING TO LEGACY MARKS TABLE
-- 1. Aligns existing legacy rows in marks/report with deterministic attempt labels
-- 2. Verifies distinct normalized exam sittings do not collapse into identical legacy exam_type
-- 3. Unpivots normalized core subject scores into legacy marks columns
-- 4. Performs strict per-row, per-subject score reconciliation and historical Others verification
-- ============================================================
DO $$
DECLARE
    v_collision_count INTEGER;
    r RECORD;
    v_exam_type VARCHAR(50);
    v_existing_count INTEGER;
    v_mark_id INTEGER;
    v_missing_sittings INTEGER;
    v_duplicate_sittings INTEGER;
    v_mismatched_scores INTEGER;
    v_norm_score_count INTEGER;
    v_matched_score_count INTEGER;
    v_mismatched_others INTEGER;
    v_archive_count INTEGER;
    v_verified_archive_matches INTEGER;
BEGIN
    -- 1. Align existing legacy marks and report rows with their deterministic attempt labels
    -- based on legacy_marks_archive ranking (matching migration 002 Step 4)
    UPDATE marks m
    SET exam_type = rnk.base_exam_type || ' (Attempt ' || rnk.attempt_num || ')'
    FROM (
        SELECT 
            original_mark_id,
            exam_type AS base_exam_type,
            ROW_NUMBER() OVER (
                PARTITION BY reg_no, exam_type 
                ORDER BY original_mark_id ASC
            )::integer AS attempt_num
        FROM legacy_marks_archive
    ) rnk
    WHERE m.mark_id = rnk.original_mark_id AND rnk.attempt_num > 1;

    -- Keep report table aligned with marks.exam_type for existing records
    UPDATE report rep
    SET exam_type = m.exam_type
    FROM marks m
    WHERE rep.mark_id = m.mark_id;

    -- 2. Collision pre-check across normalized exam sittings
    SELECT COUNT(*) INTO v_collision_count
    FROM (
        SELECT 
            m.reg_no,
            CASE 
                WHEN m.attempt_number > 1 THEN m.exam_type || ' (Attempt ' || m.attempt_number || ')'
                WHEN m.academic_year <> '2026-2027' THEN m.exam_type || ' (' || m.academic_year || ')'
                ELSE m.exam_type
            END AS computed_exam_type
        FROM (
            SELECT DISTINCT reg_no, exam_type, academic_year, attempt_number
            FROM student_subject_marks
        ) m
        GROUP BY m.reg_no, computed_exam_type
        HAVING COUNT(*) > 1
    ) coll;

    IF v_collision_count > 0 THEN
        RAISE EXCEPTION 'ROLLBACK ABORTED: % exam label collision(s) detected across normalized sittings! Multiple sittings would collapse into identical legacy exam_type.', 
            v_collision_count;
    END IF;

    -- 3. Process each distinct normalized exam sitting
    FOR r IN
        SELECT 
            m.reg_no,
            m.exam_type,
            m.academic_year,
            m.attempt_number,
            MAX(CASE WHEN sub.subject_code = 'FL101' THEN m.marks_obtained END) AS fl,
            MAX(CASE WHEN sub.subject_code = 'SL102' THEN m.marks_obtained END) AS sl,
            MAX(CASE WHEN sub.subject_code = 'MTH103' THEN m.marks_obtained END) AS math,
            MAX(CASE WHEN sub.subject_code = 'SCI104' THEN m.marks_obtained END) AS sci,
            MAX(CASE WHEN sub.subject_code = 'ART105' THEN m.marks_obtained END) AS arts
        FROM student_subject_marks m
        JOIN subjects sub ON m.subject_id = sub.subject_id
        GROUP BY m.reg_no, m.exam_type, m.academic_year, m.attempt_number
    LOOP
        -- Determine legacy exam_type string incorporating attempt / academic year if needed
        IF r.attempt_number > 1 THEN
            v_exam_type := r.exam_type || ' (Attempt ' || r.attempt_number || ')';
        ELSIF r.academic_year <> '2026-2027' THEN
            v_exam_type := r.exam_type || ' (' || r.academic_year || ')';
        ELSE
            v_exam_type := r.exam_type;
        END IF;

        -- Check how many rows in marks currently match (reg_no, v_exam_type)
        SELECT COUNT(*) INTO v_existing_count
        FROM marks
        WHERE reg_no = r.reg_no AND exam_type = v_exam_type;

        IF v_existing_count > 1 THEN
            RAISE EXCEPTION 'ROLLBACK ABORTED: Ambiguous target! Found % legacy marks rows for student % and exam %.',
                v_existing_count, r.reg_no, v_exam_type;
        ELSIF v_existing_count = 1 THEN
            -- Update the existing legacy row with normalized scores
            UPDATE marks
            SET first_language = COALESCE(r.fl, first_language),
                second_language = COALESCE(r.sl, second_language),
                mathematics = COALESCE(r.math, mathematics),
                science = COALESCE(r.sci, science),
                arts = COALESCE(r.arts, arts)
            WHERE reg_no = r.reg_no AND exam_type = v_exam_type
            RETURNING mark_id INTO v_mark_id;
        ELSE
            -- Insert newly created normalized sitting into legacy marks table
            INSERT INTO marks (reg_no, exam_type, first_language, second_language, mathematics, science, arts, others)
            VALUES (r.reg_no, v_exam_type, COALESCE(r.fl, 0), COALESCE(r.sl, 0), COALESCE(r.math, 0), COALESCE(r.sci, 0), COALESCE(r.arts, 0), 0)
            RETURNING mark_id INTO v_mark_id;

            -- Maintain corresponding report entry
            INSERT INTO report (mark_id, reg_no, exam_type)
            VALUES (v_mark_id, r.reg_no, v_exam_type)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    -- -------------------------------------------------------------
    -- 4. MANDATORY RECONCILIATION & LOSSLESS PRESERVATION CHECKS
    -- Replaces NULL-sensitive aggregate sums with exact comparisons
    -- -------------------------------------------------------------

    -- A. Missing and duplicate sitting verification
    -- Asserts that every distinct normalized exam sitting is restored to exactly one row in marks.
    -- Unrelated legacy marks rows (not part of student_subject_marks) do not cause false failures.
    SELECT COUNT(*) INTO v_missing_sittings
    FROM (
        SELECT DISTINCT 
            m.reg_no,
            CASE 
                WHEN m.attempt_number > 1 THEN m.exam_type || ' (Attempt ' || m.attempt_number || ')'
                WHEN m.academic_year <> '2026-2027' THEN m.exam_type || ' (' || m.academic_year || ')'
                ELSE m.exam_type
            END AS expected_legacy_exam_type
        FROM student_subject_marks m
    ) s
    LEFT JOIN marks mk ON mk.reg_no = s.reg_no AND mk.exam_type = s.expected_legacy_exam_type
    WHERE mk.mark_id IS NULL;

    IF v_missing_sittings > 0 THEN
        RAISE EXCEPTION 'ROLLBACK INTEGRITY ERROR: Found % normalized exam sitting(s) missing from restored marks table!',
            v_missing_sittings;
    END IF;

    SELECT COUNT(*) INTO v_duplicate_sittings
    FROM (
        SELECT 
            s.reg_no,
            s.expected_legacy_exam_type,
            COUNT(mk.mark_id) AS match_count
        FROM (
            SELECT DISTINCT 
                m.reg_no,
                CASE 
                    WHEN m.attempt_number > 1 THEN m.exam_type || ' (Attempt ' || m.attempt_number || ')'
                    WHEN m.academic_year <> '2026-2027' THEN m.exam_type || ' (' || m.academic_year || ')'
                    ELSE m.exam_type
                END AS expected_legacy_exam_type
            FROM student_subject_marks m
        ) s
        JOIN marks mk ON mk.reg_no = s.reg_no AND mk.exam_type = s.expected_legacy_exam_type
        GROUP BY s.reg_no, s.expected_legacy_exam_type
        HAVING COUNT(mk.mark_id) > 1
    ) d;

    IF v_duplicate_sittings > 0 THEN
        RAISE EXCEPTION 'ROLLBACK INTEGRITY ERROR: Found % normalized exam sitting(s) duplicated in restored marks table!',
            v_duplicate_sittings;
    END IF;

    -- B. Per-row, per-subject score comparison across all 5 core subjects
    -- Uses IS NOT DISTINCT FROM to safely handle 0, NULL, and exact integer values without masking
    SELECT COUNT(*) INTO v_mismatched_scores
    FROM (
        SELECT 
            m.reg_no,
            CASE 
                WHEN m.attempt_number > 1 THEN m.exam_type || ' (Attempt ' || m.attempt_number || ')'
                WHEN m.academic_year <> '2026-2027' THEN m.exam_type || ' (' || m.academic_year || ')'
                ELSE m.exam_type
            END AS expected_legacy_exam_type,
            sub.subject_code,
            m.marks_obtained
        FROM student_subject_marks m
        JOIN subjects sub ON m.subject_id = sub.subject_id
    ) norm
    JOIN marks mk ON mk.reg_no = norm.reg_no AND mk.exam_type = norm.expected_legacy_exam_type
    WHERE (
        (norm.subject_code = 'FL101'  AND mk.first_language  IS DISTINCT FROM norm.marks_obtained) OR
        (norm.subject_code = 'SL102'  AND mk.second_language IS DISTINCT FROM norm.marks_obtained) OR
        (norm.subject_code = 'MTH103' AND mk.mathematics     IS DISTINCT FROM norm.marks_obtained) OR
        (norm.subject_code = 'SCI104' AND mk.science         IS DISTINCT FROM norm.marks_obtained) OR
        (norm.subject_code = 'ART105' AND mk.arts            IS DISTINCT FROM norm.marks_obtained)
    );

    IF v_mismatched_scores > 0 THEN
        RAISE EXCEPTION 'ROLLBACK INTEGRITY ERROR: Found % core subject score mismatch(es) between student_subject_marks and restored marks!',
            v_mismatched_scores;
    END IF;

    -- C. Total core score count check
    SELECT COUNT(*) INTO v_norm_score_count FROM student_subject_marks;
    SELECT COUNT(*) INTO v_matched_score_count
    FROM (
        SELECT 
            m.reg_no,
            CASE 
                WHEN m.attempt_number > 1 THEN m.exam_type || ' (Attempt ' || m.attempt_number || ')'
                WHEN m.academic_year <> '2026-2027' THEN m.exam_type || ' (' || m.academic_year || ')'
                ELSE m.exam_type
            END AS expected_legacy_exam_type,
            sub.subject_code,
            m.marks_obtained
        FROM student_subject_marks m
        JOIN subjects sub ON m.subject_id = sub.subject_id
    ) norm
    JOIN marks mk ON mk.reg_no = norm.reg_no AND mk.exam_type = norm.expected_legacy_exam_type
    WHERE (
        (norm.subject_code = 'FL101'  AND mk.first_language  IS NOT DISTINCT FROM norm.marks_obtained) OR
        (norm.subject_code = 'SL102'  AND mk.second_language IS NOT DISTINCT FROM norm.marks_obtained) OR
        (norm.subject_code = 'MTH103' AND mk.mathematics     IS NOT DISTINCT FROM norm.marks_obtained) OR
        (norm.subject_code = 'SCI104' AND mk.science         IS NOT DISTINCT FROM norm.marks_obtained) OR
        (norm.subject_code = 'ART105' AND mk.arts            IS NOT DISTINCT FROM norm.marks_obtained)
    );

    IF v_matched_score_count <> v_norm_score_count THEN
        RAISE EXCEPTION 'ROLLBACK INTEGRITY ERROR: Verified core subject score count (%) does not match student_subject_marks count (%)!',
            v_matched_score_count, v_norm_score_count;
    END IF;

    -- D. Historical 'Others' preservation check
    -- Every row in legacy_marks_archive must match restored marks.others (handles Populated, Zero, and NULL)
    SELECT COUNT(*) INTO v_mismatched_others
    FROM legacy_marks_archive a
    JOIN marks m ON a.original_mark_id = m.mark_id
    WHERE m.others IS DISTINCT FROM a.marks_obtained;

    IF v_mismatched_others > 0 THEN
        RAISE EXCEPTION 'ROLLBACK INTEGRITY ERROR: Found % historical Others score mismatch(es) between legacy_marks_archive and restored marks!',
            v_mismatched_others;
    END IF;

    SELECT COUNT(*) INTO v_archive_count FROM legacy_marks_archive;
    SELECT COUNT(*) INTO v_verified_archive_matches
    FROM legacy_marks_archive a
    JOIN marks m ON a.original_mark_id = m.mark_id
    WHERE m.others IS NOT DISTINCT FROM a.marks_obtained;

    IF v_verified_archive_matches <> v_archive_count THEN
        RAISE EXCEPTION 'ROLLBACK INTEGRITY ERROR: Verified historical Others row count (%) does not match total archive count (%)!',
            v_verified_archive_matches, v_archive_count;
    END IF;
END $$;

-- ============================================================
-- STEP 5: RESTORE LEGACY STUDENT_REPORTS VIEW
-- Re-links to 6 subjects and divisor 6.0
-- ============================================================
DROP VIEW IF EXISTS student_reports;
CREATE VIEW student_reports AS
SELECT
    r.report_id,
    r.reg_no,
    s.full_name,
    m.mark_id,
    m.exam_type,
    (m.first_language + m.second_language + m.mathematics + m.science + m.arts + COALESCE(m.others, 0)) AS total_marks,
    ROUND((m.first_language + m.second_language + m.mathematics + m.science + m.arts + COALESCE(m.others, 0)) / 6.0, 2) AS average,
    CASE
        WHEN (m.first_language + m.second_language + m.mathematics + m.science + m.arts + COALESCE(m.others, 0)) / 6.0 >= 90 THEN 'A+'
        WHEN (m.first_language + m.second_language + m.mathematics + m.science + m.arts + COALESCE(m.others, 0)) / 6.0 >= 80 THEN 'A'
        WHEN (m.first_language + m.second_language + m.mathematics + m.science + m.arts + COALESCE(m.others, 0)) / 6.0 >= 70 THEN 'B'
        WHEN (m.first_language + m.second_language + m.mathematics + m.science + m.arts + COALESCE(m.others, 0)) / 6.0 >= 60 THEN 'C'
        WHEN (m.first_language + m.second_language + m.mathematics + m.science + m.arts + COALESCE(m.others, 0)) / 6.0 >= 50 THEN 'D'
        ELSE 'F'
    END AS grade
FROM report r
JOIN marks m ON r.mark_id = m.mark_id
JOIN student s ON r.reg_no = s.reg_no;

-- ============================================================
-- STEP 6: RESTORE REPORT CONSTRAINTS
-- Clean orphan reports, restore mark_id NOT NULL and foreign key
-- ============================================================
DELETE FROM report WHERE mark_id IS NULL;
ALTER TABLE report ALTER COLUMN mark_id SET NOT NULL;
ALTER TABLE report DROP CONSTRAINT IF EXISTS uq_report_sitting;
ALTER TABLE report ADD CONSTRAINT uq_report_mark UNIQUE (mark_id);
ALTER TABLE report ADD CONSTRAINT fk_report_marks FOREIGN KEY (mark_id) REFERENCES marks(mark_id) ON DELETE CASCADE;

-- ============================================================
-- STEP 7: CONSOLIDATE ATTENDANCE BEFORE RESTORING DAILY CONSTRAINT
-- Prevents duplicate key errors if students had multiple subject records on the same date.
-- Full preservation: archives 100% of Subject attendance records and deduplicated records
-- into rollback_subject_attendance_archive before consolidating.
-- ============================================================
CREATE TABLE IF NOT EXISTS rollback_subject_attendance_archive (
    archive_id SERIAL PRIMARY KEY,
    original_attend_id INTEGER,
    reg_no VARCHAR(15),
    attendance_date DATE,
    status VARCHAR(10),
    subject_id INTEGER,
    timetable_id INTEGER,
    assignment_id INTEGER,
    attendance_type VARCHAR(20),
    recorded_by VARCHAR(15),
    archived_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Archive all Subject records and any records that would be removed by deduplication
INSERT INTO rollback_subject_attendance_archive (
    original_attend_id, reg_no, attendance_date, status, subject_id, timetable_id, assignment_id, attendance_type, recorded_by
)
SELECT 
    attend_id, reg_no, attendance_date, status, subject_id, timetable_id, assignment_id, attendance_type, recorded_by
FROM attendance
WHERE attendance_type = 'Subject'
   OR attend_id NOT IN (
       SELECT MIN(attend_id)
       FROM attendance
       GROUP BY reg_no, attendance_date
   );

-- Verification assertion
DO $$
DECLARE
    v_subject_count INTEGER;
    v_archived_subject_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_subject_count FROM attendance WHERE attendance_type = 'Subject';
    SELECT COUNT(*) INTO v_archived_subject_count FROM rollback_subject_attendance_archive WHERE attendance_type = 'Subject';
    IF v_archived_subject_count < v_subject_count THEN
        RAISE EXCEPTION 'ROLLBACK INTEGRITY ERROR: Subject attendance archive count (%) is less than active subject records (%)!',
            v_archived_subject_count, v_subject_count;
    END IF;
END $$;

-- Deduplicate attendance by retaining the earliest attendance record per student per date
DELETE FROM attendance a
WHERE a.attend_id NOT IN (
    SELECT MIN(attend_id)
    FROM attendance
    GROUP BY reg_no, attendance_date
);

-- Drop partial indexes
DROP INDEX IF EXISTS uq_attendance_general;
DROP INDEX IF EXISTS uq_attendance_subject_daily;
DROP INDEX IF EXISTS uq_attendance_subject_period;
DROP INDEX IF EXISTS idx_attendance_subject_date;
DROP INDEX IF EXISTS idx_attendance_student_date;

-- Restore legacy daily uniqueness constraint
ALTER TABLE attendance ADD CONSTRAINT uq_student_attendance_date UNIQUE (reg_no, attendance_date);

-- Drop extra columns from attendance safely
ALTER TABLE attendance DROP COLUMN IF EXISTS subject_id;
ALTER TABLE attendance DROP COLUMN IF EXISTS timetable_id;
ALTER TABLE attendance DROP COLUMN IF EXISTS assignment_id;
ALTER TABLE attendance DROP COLUMN IF EXISTS attendance_type;
ALTER TABLE attendance DROP COLUMN IF EXISTS recorded_by;

-- ============================================================
-- STEP 8: RETIRE NORMALIZED TABLE
-- ============================================================
DO $$
DECLARE
    v_dependent_count INTEGER;
    v_dependents TEXT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'student_subject_marks' AND relkind = 'r') THEN
        SELECT COUNT(*), string_agg(dependent_view.relname, ', ')
        INTO v_dependent_count, v_dependents
        FROM pg_depend 
        JOIN pg_rewrite ON pg_depend.objid = pg_rewrite.oid 
        JOIN pg_class AS dependent_view ON pg_rewrite.ev_class = dependent_view.oid 
        WHERE pg_depend.refobjid = 'student_subject_marks'::regclass 
          AND dependent_view.oid != 'student_subject_marks'::regclass;

        IF v_dependent_count > 0 THEN
            RAISE EXCEPTION 'ROLLBACK SAFETY HALT: Cannot drop student_subject_marks table because % dependent object(s) rely on it: [%]. Refusing to silently drop dependent objects with CASCADE.',
                v_dependent_count, v_dependents;
        END IF;
    END IF;
END $$;

DROP TABLE IF EXISTS student_subject_marks;

COMMIT;
