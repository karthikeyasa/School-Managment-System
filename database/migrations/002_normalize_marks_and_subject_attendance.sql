-- ============================================================
-- MIGRATION 002: NORMALIZE MARKS, REMOVE OTHERS, & INTRODUCE SUBJECT ATTENDANCE
-- Database: PostgreSQL (school_management / school_management_test)
-- Safe, additive, idempotent migration script with full transactional guarantee
-- ============================================================

BEGIN;

-- ============================================================
-- STEP 1: UNMATCHED CLASS SYNC
-- Ensures every student.class maps to a valid classes.class_id
-- ============================================================
DO $$
DECLARE
    r RECORD;
    c_name VARCHAR(20);
    c_sec VARCHAR(10);
    c_code VARCHAR(30);
BEGIN
    FOR r IN
        SELECT DISTINCT s.class
        FROM student s
        LEFT JOIN classes c ON UPPER(TRIM(c.class_code)) = UPPER(TRIM(s.class))
        WHERE c.class_id IS NULL AND s.class IS NOT NULL AND TRIM(s.class) <> ''
    LOOP
        c_code := TRIM(r.class);
        IF POSITION(' ' IN c_code) > 0 THEN
            c_name := SPLIT_PART(c_code, ' ', 1);
            c_sec := SPLIT_PART(c_code, ' ', 2);
            IF c_sec = '' THEN c_sec := 'A'; END IF;
        ELSE
            c_name := c_code;
            c_sec := 'A';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM classes 
            WHERE class_code = c_code OR (class_name = c_name AND section = c_sec AND academic_year = '2026-2027')
        ) THEN
            INSERT INTO classes (class_name, section, academic_year, class_code)
            VALUES (c_name, c_sec, '2026-2027', c_code);
        END IF;
    END LOOP;
END $$;

-- ============================================================
-- STEP 2: FULL HISTORICAL 'OTHERS' ARCHIVE
-- Preserves 100% of rows (Populated, Zero, and Null) with student and exam context
-- ============================================================
CREATE TABLE IF NOT EXISTS legacy_marks_archive (
    archive_id SERIAL PRIMARY KEY,
    original_mark_id INTEGER NOT NULL,
    reg_no VARCHAR(15) NOT NULL,
    exam_type VARCHAR(30) NOT NULL,
    subject_code VARCHAR(20) NOT NULL DEFAULT 'OTH106',
    subject_name VARCHAR(50) NOT NULL DEFAULT 'Others',
    marks_obtained INTEGER NULL,
    status VARCHAR(20) NOT NULL,
    archived_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO legacy_marks_archive (original_mark_id, reg_no, exam_type, marks_obtained, status)
SELECT 
    m.mark_id, 
    m.reg_no, 
    m.exam_type, 
    m.others,
    CASE 
        WHEN m.others IS NULL THEN 'Null'
        WHEN m.others = 0 THEN 'Zero'
        ELSE 'Populated'
    END AS status
FROM marks m
WHERE NOT EXISTS (
    SELECT 1 FROM legacy_marks_archive a WHERE a.original_mark_id = m.mark_id
);

-- ============================================================
-- STEP 3: CREATE NORMALIZED MARKS TABLE
-- Stores individual subject scores with attempt and academic year support
-- ============================================================
CREATE TABLE IF NOT EXISTS student_subject_marks (
    mark_record_id SERIAL PRIMARY KEY,
    reg_no VARCHAR(15) NOT NULL REFERENCES student(reg_no) ON DELETE CASCADE,
    subject_id INTEGER NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
    exam_type VARCHAR(30) NOT NULL,
    academic_year VARCHAR(20) NOT NULL DEFAULT '2026-2027',
    attempt_number INTEGER NOT NULL DEFAULT 1,
    marks_obtained INTEGER NOT NULL CHECK (marks_obtained >= 0 AND marks_obtained <= 100),
    recorded_by VARCHAR(15) REFERENCES teacher(teacher_id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_student_subject_exam_attempt 
        UNIQUE (reg_no, subject_id, exam_type, academic_year, attempt_number)
);

CREATE INDEX IF NOT EXISTS idx_sub_marks_student ON student_subject_marks(reg_no);
CREATE INDEX IF NOT EXISTS idx_sub_marks_subject ON student_subject_marks(subject_id);
CREATE INDEX IF NOT EXISTS idx_sub_marks_exam ON student_subject_marks(exam_type, academic_year);

-- ============================================================
-- STEP 4: MIGRATE 5 CORE SUBJECT SCORES INTO NORMALIZED TABLE
-- Deterministically assigns attempt_number using ROW_NUMBER() partitioned by (reg_no, exam_type)
-- ordered by original mark_id ASC. Preserves 100% of multiple exam sittings and retakes.
-- ============================================================
DO $$
BEGIN
    -- Temporary CTE table for ranked legacy marks
    CREATE TEMP TABLE tmp_ranked_legacy_marks ON COMMIT DROP AS
    SELECT 
        m.mark_id,
        m.reg_no,
        m.exam_type,
        '2026-2027'::varchar(20) AS academic_year,
        ROW_NUMBER() OVER (
            PARTITION BY m.reg_no, m.exam_type 
            ORDER BY m.mark_id ASC
        )::integer AS attempt_number,
        m.first_language,
        m.second_language,
        m.mathematics,
        m.science,
        m.arts
    FROM marks m;
END $$;

-- First Language (FL101)
INSERT INTO student_subject_marks (reg_no, subject_id, exam_type, academic_year, attempt_number, marks_obtained)
SELECT rm.reg_no, s.subject_id, rm.exam_type, rm.academic_year, rm.attempt_number, rm.first_language
FROM tmp_ranked_legacy_marks rm, subjects s
WHERE s.subject_code = 'FL101' AND rm.first_language IS NOT NULL
ON CONFLICT (reg_no, subject_id, exam_type, academic_year, attempt_number) 
DO UPDATE SET
    marks_obtained = EXCLUDED.marks_obtained,
    updated_at = CURRENT_TIMESTAMP;

-- Second Language (SL102)
INSERT INTO student_subject_marks (reg_no, subject_id, exam_type, academic_year, attempt_number, marks_obtained)
SELECT rm.reg_no, s.subject_id, rm.exam_type, rm.academic_year, rm.attempt_number, rm.second_language
FROM tmp_ranked_legacy_marks rm, subjects s
WHERE s.subject_code = 'SL102' AND rm.second_language IS NOT NULL
ON CONFLICT (reg_no, subject_id, exam_type, academic_year, attempt_number) 
DO UPDATE SET
    marks_obtained = EXCLUDED.marks_obtained,
    updated_at = CURRENT_TIMESTAMP;

-- Mathematics (MTH103)
INSERT INTO student_subject_marks (reg_no, subject_id, exam_type, academic_year, attempt_number, marks_obtained)
SELECT rm.reg_no, s.subject_id, rm.exam_type, rm.academic_year, rm.attempt_number, rm.mathematics
FROM tmp_ranked_legacy_marks rm, subjects s
WHERE s.subject_code = 'MTH103' AND rm.mathematics IS NOT NULL
ON CONFLICT (reg_no, subject_id, exam_type, academic_year, attempt_number) 
DO UPDATE SET
    marks_obtained = EXCLUDED.marks_obtained,
    updated_at = CURRENT_TIMESTAMP;

-- Science (SCI104)
INSERT INTO student_subject_marks (reg_no, subject_id, exam_type, academic_year, attempt_number, marks_obtained)
SELECT rm.reg_no, s.subject_id, rm.exam_type, rm.academic_year, rm.attempt_number, rm.science
FROM tmp_ranked_legacy_marks rm, subjects s
WHERE s.subject_code = 'SCI104' AND rm.science IS NOT NULL
ON CONFLICT (reg_no, subject_id, exam_type, academic_year, attempt_number) 
DO UPDATE SET
    marks_obtained = EXCLUDED.marks_obtained,
    updated_at = CURRENT_TIMESTAMP;

-- Arts (ART105)
INSERT INTO student_subject_marks (reg_no, subject_id, exam_type, academic_year, attempt_number, marks_obtained)
SELECT rm.reg_no, s.subject_id, rm.exam_type, rm.academic_year, rm.attempt_number, rm.arts
FROM tmp_ranked_legacy_marks rm, subjects s
WHERE s.subject_code = 'ART105' AND rm.arts IS NOT NULL
ON CONFLICT (reg_no, subject_id, exam_type, academic_year, attempt_number) 
DO UPDATE SET
    marks_obtained = EXCLUDED.marks_obtained,
    updated_at = CURRENT_TIMESTAMP;

-- ============================================================
-- STEP 5: EVOLVE REPORT TABLE (Maintains Stable report_id)
-- Aligns canonical exam sittings with tmp_ranked_legacy_marks
-- ============================================================
ALTER TABLE report ADD COLUMN IF NOT EXISTS exam_type VARCHAR(50);
ALTER TABLE report ADD COLUMN IF NOT EXISTS academic_year VARCHAR(20) NOT NULL DEFAULT '2026-2027';
ALTER TABLE report ADD COLUMN IF NOT EXISTS attempt_number INTEGER NOT NULL DEFAULT 1;

-- Backfill exam_type, academic_year, and attempt_number from tmp_ranked_legacy_marks
UPDATE report r
SET 
    exam_type = rm.exam_type,
    academic_year = rm.academic_year,
    attempt_number = rm.attempt_number
FROM tmp_ranked_legacy_marks rm
WHERE r.mark_id = rm.mark_id;

-- If any report record lacks exam_type (e.g. orphan records without mark_id), default safely
UPDATE report SET exam_type = 'Final Exam' WHERE exam_type IS NULL;

-- Safe removal of legacy foreign key constraint to marks(mark_id)
ALTER TABLE report DROP CONSTRAINT IF EXISTS fk_report_marks;
ALTER TABLE report DROP CONSTRAINT IF EXISTS uq_report_mark;
ALTER TABLE report ALTER COLUMN mark_id DROP NOT NULL;

-- Add uniqueness constraint for canonical exam sitting
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_report_sitting'
    ) THEN
        ALTER TABLE report ADD CONSTRAINT uq_report_sitting 
        UNIQUE (reg_no, exam_type, academic_year, attempt_number);
    END IF;
END $$;

-- Backfill report entries for any normalized marks sittings not yet represented in report
INSERT INTO report (reg_no, exam_type, academic_year, attempt_number)
SELECT DISTINCT m.reg_no, m.exam_type, m.academic_year, m.attempt_number
FROM student_subject_marks m
WHERE NOT EXISTS (
    SELECT 1 FROM report r 
    WHERE r.reg_no = m.reg_no 
      AND r.exam_type = m.exam_type 
      AND r.academic_year = m.academic_year 
      AND r.attempt_number = m.attempt_number
);

-- ============================================================
-- STEP 6: MANDATORY RECONCILIATION & LOSSLESS PRESERVATION CHECKS
-- Aborts transaction with detailed error if any score or row was dropped
-- ============================================================
DO $$
DECLARE
    v_marks_count INTEGER;
    v_archive_count INTEGER;
    v_expected_fl INTEGER;
    v_actual_fl INTEGER;
    v_expected_sl INTEGER;
    v_actual_sl INTEGER;
    v_expected_math INTEGER;
    v_actual_math INTEGER;
    v_expected_sci INTEGER;
    v_actual_sci INTEGER;
    v_expected_art INTEGER;
    v_actual_art INTEGER;
    v_mismatched_scores INTEGER;
    v_expected_total_scores INTEGER;
    v_actual_total_scores INTEGER;
    v_unpopulated_reports INTEGER;
BEGIN
    -- 1. Archive count must equal legacy marks count
    SELECT COUNT(*) INTO v_marks_count FROM marks;
    SELECT COUNT(*) INTO v_archive_count FROM legacy_marks_archive;
    IF v_marks_count <> v_archive_count THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: Archive count (%) does not match legacy marks count (%)!', 
            v_archive_count, v_marks_count;
    END IF;

    -- 2. Verify First Language non-null count
    SELECT COUNT(*) INTO v_expected_fl FROM marks WHERE first_language IS NOT NULL;
    SELECT COUNT(*) INTO v_actual_fl FROM student_subject_marks m JOIN subjects s ON m.subject_id = s.subject_id WHERE s.subject_code = 'FL101';
    IF v_expected_fl <> v_actual_fl THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: FL101 migrated count (%) does not match legacy non-null count (%)!', 
            v_actual_fl, v_expected_fl;
    END IF;

    -- 3. Verify Second Language non-null count
    SELECT COUNT(*) INTO v_expected_sl FROM marks WHERE second_language IS NOT NULL;
    SELECT COUNT(*) INTO v_actual_sl FROM student_subject_marks m JOIN subjects s ON m.subject_id = s.subject_id WHERE s.subject_code = 'SL102';
    IF v_expected_sl <> v_actual_sl THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: SL102 migrated count (%) does not match legacy non-null count (%)!', 
            v_actual_sl, v_expected_sl;
    END IF;

    -- 4. Verify Mathematics non-null count
    SELECT COUNT(*) INTO v_expected_math FROM marks WHERE mathematics IS NOT NULL;
    SELECT COUNT(*) INTO v_actual_math FROM student_subject_marks m JOIN subjects s ON m.subject_id = s.subject_id WHERE s.subject_code = 'MTH103';
    IF v_expected_math <> v_actual_math THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: MTH103 migrated count (%) does not match legacy non-null count (%)!', 
            v_actual_math, v_expected_math;
    END IF;

    -- 5. Verify Science non-null count
    SELECT COUNT(*) INTO v_expected_sci FROM marks WHERE science IS NOT NULL;
    SELECT COUNT(*) INTO v_actual_sci FROM student_subject_marks m JOIN subjects s ON m.subject_id = s.subject_id WHERE s.subject_code = 'SCI104';
    IF v_expected_sci <> v_actual_sci THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: SCI104 migrated count (%) does not match legacy non-null count (%)!', 
            v_actual_sci, v_expected_sci;
    END IF;

    -- 6. Verify Arts non-null count
    SELECT COUNT(*) INTO v_expected_art FROM marks WHERE arts IS NOT NULL;
    SELECT COUNT(*) INTO v_actual_art FROM student_subject_marks m JOIN subjects s ON m.subject_id = s.subject_id WHERE s.subject_code = 'ART105';
    IF v_expected_art <> v_actual_art THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: ART105 migrated count (%) does not match legacy non-null count (%)!', 
            v_actual_art, v_expected_art;
    END IF;

    -- 7. Exact per-row, per-subject score reconciliation
    -- Asserts that for every legacy mark row and every core subject, the normalized marks_obtained
    -- matches the legacy value exactly (handling NULL, zero, and populated scores with IS NOT DISTINCT FROM)
    SELECT COUNT(*) INTO v_mismatched_scores
    FROM (
        SELECT rm.reg_no, rm.exam_type, rm.academic_year, rm.attempt_number, 'FL101' AS subject_code, rm.first_language AS expected_score
        FROM tmp_ranked_legacy_marks rm WHERE rm.first_language IS NOT NULL
        UNION ALL
        SELECT rm.reg_no, rm.exam_type, rm.academic_year, rm.attempt_number, 'SL102', rm.second_language
        FROM tmp_ranked_legacy_marks rm WHERE rm.second_language IS NOT NULL
        UNION ALL
        SELECT rm.reg_no, rm.exam_type, rm.academic_year, rm.attempt_number, 'MTH103', rm.mathematics
        FROM tmp_ranked_legacy_marks rm WHERE rm.mathematics IS NOT NULL
        UNION ALL
        SELECT rm.reg_no, rm.exam_type, rm.academic_year, rm.attempt_number, 'SCI104', rm.science
        FROM tmp_ranked_legacy_marks rm WHERE rm.science IS NOT NULL
        UNION ALL
        SELECT rm.reg_no, rm.exam_type, rm.academic_year, rm.attempt_number, 'ART105', rm.arts
        FROM tmp_ranked_legacy_marks rm WHERE rm.arts IS NOT NULL
    ) exp
    LEFT JOIN (
        SELECT m.reg_no, m.exam_type, m.academic_year, m.attempt_number, s.subject_code, m.marks_obtained
        FROM student_subject_marks m
        JOIN subjects s ON m.subject_id = s.subject_id
    ) act 
      ON exp.reg_no = act.reg_no 
     AND exp.exam_type = act.exam_type 
     AND exp.academic_year = act.academic_year 
     AND exp.attempt_number = act.attempt_number 
     AND exp.subject_code = act.subject_code
    WHERE act.marks_obtained IS DISTINCT FROM exp.expected_score;

    IF v_mismatched_scores > 0 THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: Found % per-row, per-subject score mismatch(es) between legacy marks and student_subject_marks!',
            v_mismatched_scores;
    END IF;

    -- Verify total score count equality across all 5 core subjects
    SELECT (
        COUNT(first_language) + 
        COUNT(second_language) + 
        COUNT(mathematics) + 
        COUNT(science) + 
        COUNT(arts)
    ) INTO v_expected_total_scores
    FROM marks;

    SELECT COUNT(*) INTO v_actual_total_scores
    FROM student_subject_marks;

    IF v_expected_total_scores <> v_actual_total_scores THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: Total migrated score count (%) does not match legacy score count (%)!',
            v_actual_total_scores, v_expected_total_scores;
    END IF;

    -- 8. Report integrity
    SELECT COUNT(*) INTO v_unpopulated_reports 
    FROM report 
    WHERE exam_type IS NULL OR academic_year IS NULL OR attempt_number IS NULL;
    IF v_unpopulated_reports > 0 THEN
        RAISE EXCEPTION 'MIGRATION INTEGRITY ERROR: Found % report record(s) with unpopulated exam_type, academic_year, or attempt_number!',
            v_unpopulated_reports;
    END IF;
END $$;

-- ============================================================
-- STEP 7: EVOLVE ATTENDANCE & CREATE PARTIAL UNIQUE INDEXES
-- Preserves legacy daily attendance without inventing fake subjects,
-- and allows subject/period attendance without collisions.
-- ============================================================
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS subject_id INTEGER REFERENCES subjects(subject_id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS timetable_id INTEGER REFERENCES timetable(timetable_id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS assignment_id INTEGER REFERENCES teacher_assignment(assignment_id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS attendance_type VARCHAR(20) NOT NULL DEFAULT 'Subject',
ADD COLUMN IF NOT EXISTS recorded_by VARCHAR(15) REFERENCES teacher(teacher_id) ON DELETE SET NULL;

-- Preserve all legacy records as 'General'
UPDATE attendance 
SET attendance_type = 'General' 
WHERE subject_id IS NULL;

-- Drop legacy table-wide daily constraint
ALTER TABLE attendance DROP CONSTRAINT IF EXISTS uq_student_attendance_date;

-- Partial unique index 1: General/Homeroom daily attendance (one per student per date)
CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_general 
ON attendance (reg_no, attendance_date) 
WHERE attendance_type = 'General';

-- Partial unique index 2: Daily subject attendance (when timetable_id is not specified)
CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_subject_daily 
ON attendance (reg_no, attendance_date, subject_id) 
WHERE attendance_type = 'Subject' AND timetable_id IS NULL AND subject_id IS NOT NULL;

-- Partial unique index 3: Period/slot-level subject attendance (when timetable_id is specified)
CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_subject_period 
ON attendance (reg_no, attendance_date, subject_id, timetable_id) 
WHERE attendance_type = 'Subject' AND timetable_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_attendance_subject_date ON attendance(subject_id, attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_student_date ON attendance(reg_no, attendance_date);

-- ============================================================
-- STEP 8: UPDATE STUDENT_REPORTS VIEW (Stable report_id, Divisor 5.0)
-- Pivots 5 core subjects, derives total, average, and grade on 5 subjects
-- ============================================================
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
            RAISE EXCEPTION 'MIGRATION SAFETY HALT: Cannot drop student_reports view because % dependent object(s) rely on it: [%]. Refusing to silently drop dependent objects with CASCADE.',
                v_dependent_count, v_dependents;
        END IF;
    END IF;
END $$;

DROP VIEW IF EXISTS student_reports;
CREATE VIEW student_reports AS
SELECT
    r.report_id,
    r.reg_no,
    s.full_name,
    s.class,
    r.exam_type,
    r.academic_year,
    r.attempt_number,
    MAX(CASE WHEN sub.subject_code = 'FL101' THEN m.marks_obtained END) AS first_language,
    MAX(CASE WHEN sub.subject_code = 'SL102' THEN m.marks_obtained END) AS second_language,
    MAX(CASE WHEN sub.subject_code = 'MTH103' THEN m.marks_obtained END) AS mathematics,
    MAX(CASE WHEN sub.subject_code = 'SCI104' THEN m.marks_obtained END) AS science,
    MAX(CASE WHEN sub.subject_code = 'ART105' THEN m.marks_obtained END) AS arts,
    COALESCE(SUM(m.marks_obtained), 0) AS total_marks,
    COALESCE(ROUND(SUM(m.marks_obtained) / 5.0, 2), 0) AS average,
    CASE
        WHEN SUM(m.marks_obtained) / 5.0 >= 90 THEN 'A+'
        WHEN SUM(m.marks_obtained) / 5.0 >= 80 THEN 'A'
        WHEN SUM(m.marks_obtained) / 5.0 >= 70 THEN 'B'
        WHEN SUM(m.marks_obtained) / 5.0 >= 60 THEN 'C'
        WHEN SUM(m.marks_obtained) / 5.0 >= 50 THEN 'D'
        ELSE 'F'
    END AS grade
FROM report r
JOIN student s ON r.reg_no = s.reg_no
LEFT JOIN student_subject_marks m 
    ON r.reg_no = m.reg_no 
   AND r.exam_type = m.exam_type 
   AND r.academic_year = m.academic_year 
   AND r.attempt_number = m.attempt_number
LEFT JOIN subjects sub ON m.subject_id = sub.subject_id
GROUP BY r.report_id, r.reg_no, s.full_name, s.class, r.exam_type, r.academic_year, r.attempt_number;

-- ============================================================
-- STEP 9: CLEAN UP OTH106 SUBJECT REFERENCES
-- Safely cleans up dependent timetable and assignment rows before deleting OTH106
-- ============================================================
DELETE FROM timetable WHERE subject_id IN (SELECT subject_id FROM subjects WHERE subject_code = 'OTH106');
DELETE FROM teacher_assignment WHERE subject_id IN (SELECT subject_id FROM subjects WHERE subject_code = 'OTH106');
DELETE FROM subjects WHERE subject_code = 'OTH106';

COMMIT;
