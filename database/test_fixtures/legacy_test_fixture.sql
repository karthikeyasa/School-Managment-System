-- ============================================================
-- DISPOSABLE LEGACY TEST FIXTURE SCRIPT
-- Target Database: school_management_test ONLY
-- Reconstructs the complete legacy schema and populates rich synthetic
-- baseline data covering every critical migration edge case:
--   1. Duplicate exam sittings for the same student (retakes)
--   2. Populated, Zero, and NULL historical 'Others' scores
--   3. Unmatched student class strings (single-word and multi-word)
--   4. Active assignments and timetable periods for retired OTH106
--   5. Legacy attendance records under uq_student_attendance_date
--   6. Legacy report records linked to legacy marks(mark_id)
-- ============================================================

-- Strict database safety guard: NEVER run against production or postgres
DO $$
BEGIN
    IF current_database() IN ('school_management', 'postgres') THEN
        RAISE EXCEPTION 'SAFETY HALT: Destructive test fixture must NEVER run against production or system database %!', current_database();
    END IF;
    IF current_database() NOT IN ('school_management_stage_b_test', 'school_management_test') THEN
        RAISE EXCEPTION 'SAFETY HALT: Attempted to run test fixture against unapproved database %! Permitted test databases: school_management_stage_b_test or school_management_test.', current_database();
    END IF;
END $$;

BEGIN;

-- Drop all existing tables/views in test database to start clean
DROP VIEW IF EXISTS student_reports CASCADE;
DROP VIEW IF EXISTS student_details CASCADE;
DROP TABLE IF EXISTS report CASCADE;
DROP TABLE IF EXISTS attendance CASCADE;
DROP TABLE IF EXISTS marks CASCADE;
DROP TABLE IF EXISTS student_subject_marks CASCADE;
DROP TABLE IF EXISTS legacy_marks_archive CASCADE;
DROP TABLE IF EXISTS rollback_subject_attendance_archive CASCADE;
DROP TABLE IF EXISTS timetable CASCADE;
DROP TABLE IF EXISTS teacher_assignment CASCADE;
DROP TABLE IF EXISTS announcements CASCADE;
DROP TABLE IF EXISTS subjects CASCADE;
DROP TABLE IF EXISTS classes CASCADE;
DROP TABLE IF EXISTS student CASCADE;
DROP TABLE IF EXISTS teacher CASCADE;
DROP TABLE IF EXISTS administrator CASCADE;

-- -------------------------
-- 1. ADMINISTRATOR
-- -------------------------
CREATE TABLE administrator (
    admin_id VARCHAR(10) PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'admin'
);

INSERT INTO administrator (admin_id, username, password, role)
VALUES ('ADM001', 'admin', '$2a$10$vQ6s2q2sYtL1mN3oP4r5u.e8k9j0w1x2y3z4a5b6c7d8e9f0g1h2i', 'admin');

-- -------------------------
-- 2. TEACHER
-- -------------------------
CREATE TABLE teacher (
    teacher_id VARCHAR(15) PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(15) NOT NULL,
    qualification VARCHAR(100),
    specialization VARCHAR(100),
    joining_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Inactive', 'Suspended')),
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO teacher (teacher_id, full_name, email, phone, qualification, specialization, status, password_hash)
VALUES 
    ('TCH001', 'Dr. Ramesh Sharma', 'ramesh@school.com', '9876543210', 'Ph.D Mathematics', 'Mathematics', 'Active', '$2a$10$abcdefghijklmnopqrstuv'),
    ('TCH002', 'Priya Nair', 'priya@school.com', '9876543211', 'M.Sc Physics', 'Science', 'Active', '$2a$10$abcdefghijklmnopqrstuv'),
    ('TCH003', 'Anil Menon', 'anil@school.com', '9876543212', 'M.A History', 'General Studies', 'Active', '$2a$10$abcdefghijklmnopqrstuv');

-- -------------------------
-- 3. CLASSES (Initial Seeded Baseline)
-- -------------------------
CREATE TABLE classes (
    class_id SERIAL PRIMARY KEY,
    class_name VARCHAR(20) NOT NULL,
    section VARCHAR(10) NOT NULL,
    academic_year VARCHAR(20) NOT NULL DEFAULT '2026-2027',
    class_code VARCHAR(30) UNIQUE NOT NULL,
    CONSTRAINT uq_class_section_year UNIQUE (class_name, section, academic_year)
);

INSERT INTO classes (class_name, section, academic_year, class_code)
VALUES 
    ('10', 'A', '2026-2027', '10 A'),
    ('10', 'B', '2026-2027', '10 B');

-- -------------------------
-- 4. STUDENT (Includes Unmatched Class Strings)
-- -------------------------
CREATE TABLE student (
    reg_no VARCHAR(15) PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    class VARCHAR(20) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender VARCHAR(10) NOT NULL CHECK (gender IN ('Male', 'Female', 'Other')),
    phone VARCHAR(15) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    admin_id VARCHAR(10) NOT NULL REFERENCES administrator(admin_id),
    house_no VARCHAR(20),
    city VARCHAR(50),
    pin VARCHAR(10)
);

INSERT INTO student (reg_no, full_name, class, date_of_birth, gender, phone, email, admin_id, house_no, city, pin)
VALUES 
    ('STU001', 'Aarav Patel', '10 A', '2010-05-15', 'Male', '9123456780', 'aarav@example.com', 'ADM001', '12', 'Bangalore', '560001'),
    ('STU002', 'Diya Sen', '10 B', '2010-08-20', 'Female', '9123456781', 'diya@example.com', 'ADM001', '34', 'Mumbai', '400001'),
    ('STU003', 'Rohan Gupta', '11 C', '2009-03-10', 'Male', '9123456782', 'rohan@example.com', 'ADM001', '56', 'Delhi', '110001'),
    ('STU004', 'Sneha Reddy', '12 Science D', '2008-11-25', 'Female', '9123456783', 'sneha@example.com', 'ADM001', '78', 'Hyderabad', '500001');

-- -------------------------
-- 5. SUBJECTS (Including Legacy OTH106)
-- -------------------------
CREATE TABLE subjects (
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
    ('OTH106', 'Others', 'General');

-- -------------------------
-- 6. TEACHER ASSIGNMENT & TIMETABLE (Including OTH106 to verify Step 9 cleanup)
-- -------------------------
CREATE TABLE teacher_assignment (
    assignment_id SERIAL PRIMARY KEY,
    teacher_id VARCHAR(15) NOT NULL REFERENCES teacher(teacher_id) ON DELETE CASCADE,
    class_id INTEGER NOT NULL REFERENCES classes(class_id) ON DELETE CASCADE,
    subject_id INTEGER NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
    academic_year VARCHAR(20) NOT NULL DEFAULT '2026-2027',
    assigned_date DATE NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uq_teacher_class_subject UNIQUE (teacher_id, class_id, subject_id, academic_year)
);

INSERT INTO teacher_assignment (teacher_id, class_id, subject_id)
VALUES 
    ('TCH001', 1, 3), -- Dr. Sharma -> 10 A Math
    ('TCH002', 1, 4), -- Priya Nair -> 10 A Science
    ('TCH003', 1, 6); -- Anil Menon -> 10 A Others (MUST BE DELETED IN MIGRATION STEP 9)

CREATE TABLE timetable (
    timetable_id SERIAL PRIMARY KEY,
    class_id INTEGER NOT NULL REFERENCES classes(class_id) ON DELETE CASCADE,
    subject_id INTEGER NOT NULL REFERENCES subjects(subject_id) ON DELETE CASCADE,
    teacher_id VARCHAR(15) NOT NULL REFERENCES teacher(teacher_id) ON DELETE CASCADE,
    day_of_week VARCHAR(15) NOT NULL CHECK (day_of_week IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    room_number VARCHAR(20),
    CONSTRAINT chk_timetable_time CHECK (end_time > start_time)
);

INSERT INTO timetable (class_id, subject_id, teacher_id, day_of_week, start_time, end_time, room_number)
VALUES 
    (1, 3, 'TCH001', 'Monday', '09:00', '10:00', 'Room 101'),
    (1, 4, 'TCH002', 'Monday', '10:00', '11:00', 'Room 101'),
    (1, 6, 'TCH003', 'Monday', '11:00', '12:00', 'Room 101'); -- OTH106 Period (MUST BE DELETED IN STEP 9)

-- -------------------------
-- 7. ANNOUNCEMENTS
-- -------------------------
CREATE TABLE announcements (
    announcement_id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    target_audience VARCHAR(20) NOT NULL DEFAULT 'All',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO announcements (title, content, created_by)
VALUES ('School Reopening', 'School reopens on Monday for all students.', 'admin');

-- -------------------------
-- 8. LEGACY MARKS TABLE
-- Covers: Populated, Zero, NULL others, and DUPLICATE exam sittings (retakes)
-- -------------------------
CREATE TABLE marks (
    mark_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reg_no VARCHAR(15) NOT NULL REFERENCES student(reg_no),
    exam_type VARCHAR(30) NOT NULL,
    first_language INTEGER NOT NULL CHECK (first_language >= 0 AND first_language <= 100),
    second_language INTEGER NOT NULL CHECK (second_language >= 0 AND second_language <= 100),
    mathematics INTEGER NOT NULL CHECK (mathematics >= 0 AND mathematics <= 100),
    science INTEGER NOT NULL CHECK (science >= 0 AND science <= 100),
    arts INTEGER NOT NULL CHECK (arts >= 0 AND arts <= 100),
    others INTEGER CHECK (others >= 0 AND others <= 100)
);

INSERT INTO marks (reg_no, exam_type, first_language, second_language, mathematics, science, arts, others)
VALUES 
    -- 1. STU001: Mid Term with populated others (84)
    ('STU001', 'Mid Term', 85, 80, 95, 90, 88, 84),
    -- 2. STU001: Final Exam Sitting 1 with zero others (0)
    ('STU001', 'Final Exam', 75, 70, 80, 78, 72, 0),
    -- 3. STU001: Final Exam Sitting 2 (DUPLICATE EXAM SITTING / RETAKE) with NULL others
    ('STU001', 'Final Exam', 88, 85, 92, 91, 89, NULL),
    -- 4. STU002: Mid Term with populated others (70)
    ('STU002', 'Mid Term', 90, 92, 94, 96, 98, 70),
    -- 5. STU003 (Unmatched class '11 C'): Mid Term with zero others (0)
    ('STU003', 'Mid Term', 60, 65, 70, 75, 80, 0),
    -- 6. STU004 (Unmatched class '12 Science D'): Mid Term with populated others (45)
    ('STU004', 'Mid Term', 50, 55, 60, 65, 70, 45);

-- -------------------------
-- 9. LEGACY REPORT TABLE
-- -------------------------
CREATE TABLE report (
    report_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mark_id INTEGER NOT NULL REFERENCES marks(mark_id),
    reg_no VARCHAR(15) NOT NULL REFERENCES student(reg_no),
    CONSTRAINT uq_report_mark UNIQUE (mark_id)
);

INSERT INTO report (mark_id, reg_no)
VALUES 
    (1, 'STU001'),
    (2, 'STU001'),
    (3, 'STU001'),
    (4, 'STU002'),
    (5, 'STU003'),
    (6, 'STU004');

-- -------------------------
-- 10. LEGACY ATTENDANCE TABLE (uq_student_attendance_date)
-- -------------------------
CREATE TABLE attendance (
    attend_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reg_no VARCHAR(15) NOT NULL REFERENCES student(reg_no) ON DELETE CASCADE,
    attendance_date DATE NOT NULL,
    status VARCHAR(10) NOT NULL CHECK (status IN ('Present', 'Absent')),
    CONSTRAINT uq_student_attendance_date UNIQUE (reg_no, attendance_date)
);

INSERT INTO attendance (reg_no, attendance_date, status)
VALUES 
    ('STU001', '2026-10-01', 'Present'),
    ('STU001', '2026-10-02', 'Absent'),
    ('STU002', '2026-10-01', 'Present'),
    ('STU003', '2026-10-01', 'Present'),
    ('STU004', '2026-10-01', 'Present');

-- -------------------------
-- 11. LEGACY VIEWS
-- -------------------------
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

CREATE VIEW student_details AS
SELECT
    reg_no,
    full_name,
    class,
    date_of_birth,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_of_birth))::INTEGER AS age,
    gender,
    phone,
    email,
    admin_id,
    house_no,
    city,
    pin
FROM student;

COMMIT;
