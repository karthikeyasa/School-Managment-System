ALTER TABLE administrator
ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'admin';

UPDATE administrator SET role = 'admin' WHERE role IS NULL;

CREATE TABLE IF NOT EXISTS teacher (
    teacher_id VARCHAR(15) PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(15) NOT NULL,
    qualification VARCHAR(100),
    specialization VARCHAR(100),
    joining_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'Active'
        CHECK (status IN ('Active', 'Inactive', 'Suspended')),
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_teacher_email
ON teacher(email);

CREATE INDEX IF NOT EXISTS idx_teacher_status
ON teacher(status);

CREATE TABLE IF NOT EXISTS classes (
    class_id SERIAL PRIMARY KEY,
    class_name VARCHAR(20) NOT NULL,
    section VARCHAR(10) NOT NULL,
    academic_year VARCHAR(20) NOT NULL DEFAULT '2026-2027',
    class_code VARCHAR(30) UNIQUE NOT NULL,
    CONSTRAINT uq_class_section_year
        UNIQUE (class_name, section, academic_year)
);

DO $$
DECLARE
    r RECORD;
    c_name VARCHAR(20);
    c_sec VARCHAR(10);
    c_code VARCHAR(30);
BEGIN
    FOR r IN
        SELECT DISTINCT class
        FROM student
        WHERE class IS NOT NULL AND TRIM(class) <> ''
    LOOP
        c_code := TRIM(r.class);

        IF POSITION(' ' IN c_code) > 0 THEN
            c_name := SPLIT_PART(c_code, ' ', 1);
            c_sec := SPLIT_PART(c_code, ' ', 2);

            IF c_sec = '' THEN
                c_sec := 'A';
            END IF;
        ELSE
            c_name := c_code;
            c_sec := 'A';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM classes
            WHERE class_code = c_code
               OR (class_name = c_name AND section = c_sec AND academic_year = '2026-2027')
        ) THEN
            INSERT INTO classes (
                class_name, section, academic_year, class_code
            )
            VALUES (
                c_name, c_sec, '2026-2027', c_code
            );
        END IF;
    END LOOP;
END $$;

CREATE TABLE IF NOT EXISTS subjects (
    subject_id SERIAL PRIMARY KEY,
    subject_code VARCHAR(20) UNIQUE NOT NULL,
    subject_name VARCHAR(100) NOT NULL,
    department VARCHAR(50)
);

INSERT INTO subjects (subject_code, subject_name, department)
VALUES
    ('FL101', 'First Language', 'Languages'),
    ('SL102', 'Second Language', 'Languages'),
    ('MTH103', 'Mathematics', 'Science & Mathematics'),
    ('SCI104', 'Science', 'Science & Mathematics'),
    ('ART105', 'Arts', 'Humanities'),
    ('OTH106', 'Others', 'General')
ON CONFLICT (subject_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS teacher_assignment (
    assignment_id SERIAL PRIMARY KEY,
    teacher_id VARCHAR(15) NOT NULL
        REFERENCES teacher(teacher_id) ON DELETE CASCADE,
    class_id INTEGER NOT NULL
        REFERENCES classes(class_id) ON DELETE CASCADE,
    subject_id INTEGER NOT NULL
        REFERENCES subjects(subject_id) ON DELETE CASCADE,
    academic_year VARCHAR(20) NOT NULL DEFAULT '2026-2027',
    assigned_date DATE NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uq_teacher_class_subject
        UNIQUE (teacher_id, class_id, subject_id, academic_year)
);

CREATE INDEX IF NOT EXISTS idx_teacher_assignment_teacher
ON teacher_assignment(teacher_id);

CREATE INDEX IF NOT EXISTS idx_teacher_assignment_class
ON teacher_assignment(class_id);

CREATE TABLE IF NOT EXISTS timetable (
    timetable_id SERIAL PRIMARY KEY,
    class_id INTEGER NOT NULL
        REFERENCES classes(class_id) ON DELETE CASCADE,
    subject_id INTEGER NOT NULL
        REFERENCES subjects(subject_id) ON DELETE CASCADE,
    teacher_id VARCHAR(15) NOT NULL
        REFERENCES teacher(teacher_id) ON DELETE CASCADE,
    day_of_week VARCHAR(15) NOT NULL
        CHECK (day_of_week IN (
            'Monday', 'Tuesday', 'Wednesday',
            'Thursday', 'Friday', 'Saturday'
        )),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    room_number VARCHAR(20),
    CONSTRAINT chk_timetable_time CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_timetable_class
ON timetable(class_id, day_of_week);

CREATE INDEX IF NOT EXISTS idx_timetable_teacher
ON timetable(teacher_id, day_of_week);

CREATE TABLE IF NOT EXISTS announcements (
    announcement_id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    target_audience VARCHAR(20) NOT NULL DEFAULT 'All'
        CHECK (target_audience IN ('All', 'Teachers', 'Students')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_announcements_active
ON announcements(is_active, target_audience);

-- ------------------------------------------------------------
-- TIMETABLE CONFLICT PROTECTION NOTE:
-- Timetable overlap prevention (class & teacher schedule conflict)
-- is validated at the application layer via backend/routes/timetable.js.
-- Direct SQL INSERTs executed outside the application are not checked
-- for overlap by PostgreSQL unless the btree_gist extension and an EXCLUDE
-- constraint are configured. Always use the API or dashboard to schedule periods.
-- ------------------------------------------------------------

-- Remove any sync trigger on marks to prevent duplicate report insertions.
-- Synchronization is consistently managed by the backend application pipeline.
DO $$
DECLARE
    trg_record RECORD;
BEGIN
    IF to_regclass('marks') IS NOT NULL THEN
        FOR trg_record IN
            SELECT t.tgname
            FROM pg_trigger t
            JOIN pg_proc p ON t.tgfoid = p.oid
            WHERE t.tgrelid = 'marks'::regclass
              AND p.proname = 'fn_sync_report_on_marks'
              AND NOT t.tgisinternal
        LOOP
            EXECUTE format('DROP TRIGGER IF EXISTS %I ON marks;', trg_record.tgname);
        END LOOP;
    END IF;
END $$;

DROP FUNCTION IF EXISTS fn_sync_report_on_marks();

-- Safe, non-destructive check before adding UNIQUE constraint on report(mark_id)
-- Ensures existing duplicates (if any) are not silently deleted or dropped
DO $$
DECLARE
    dup_count INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        WHERE c.conrelid = 'report'::regclass
          AND (
              c.conname = 'uq_report_mark'
              OR (
                  c.contype = 'u'
                  AND c.conkey = ARRAY[
                      (SELECT attnum FROM pg_attribute WHERE attrelid = 'report'::regclass AND attname = 'mark_id')
                  ]
              )
          )
    ) THEN
        SELECT COUNT(*) INTO dup_count
        FROM (
            SELECT mark_id FROM report GROUP BY mark_id HAVING COUNT(*) > 1
        ) dups;

        IF dup_count > 0 THEN
            RAISE NOTICE 'Notice: % duplicate mark_id records found in report table. uq_report_mark constraint was skipped to prevent data loss. Please resolve duplicates manually.', dup_count;
        ELSE
            ALTER TABLE report ADD CONSTRAINT uq_report_mark UNIQUE (mark_id);
        END IF;
    END IF;
END $$;

-- Safely backfill any existing marks records that do not have a report entry
INSERT INTO report (mark_id, reg_no)
SELECT m.mark_id, m.reg_no
FROM marks m
WHERE NOT EXISTS (
    SELECT 1
    FROM report r
    WHERE r.mark_id = m.mark_id
);
