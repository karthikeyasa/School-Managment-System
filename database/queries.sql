-- ============================================================
-- SCHOOL MANAGEMENT SYSTEM
-- DBMS SQL QUERY DEMONSTRATION
-- Database: school_management
-- ============================================================


-- ============================================================
-- 1. BASIC SELECT QUERIES
-- ============================================================

-- Display all students
SELECT *
FROM student;

-- Display selected student details
SELECT reg_no, full_name, class, gender
FROM student;


-- ============================================================
-- 2. WHERE CLAUSE
-- ============================================================

-- Find a particular student
SELECT *
FROM student
WHERE reg_no = 'STU001';

-- Find students belonging to a particular class
SELECT reg_no, full_name, class
FROM student
WHERE class = '10 A';


-- ============================================================
-- 3. LIKE / ILIKE
-- ============================================================

-- Search students whose name contains 'Rahul'
SELECT reg_no, full_name, class
FROM student
WHERE full_name ILIKE '%Rahul%';


-- ============================================================
-- 4. ORDER BY
-- ============================================================

-- Display students alphabetically
SELECT reg_no, full_name, class
FROM student
ORDER BY full_name ASC;

-- Display marks from highest mathematics mark to lowest
SELECT reg_no, mathematics
FROM marks
ORDER BY mathematics DESC;


-- ============================================================
-- 5. INSERT
-- ============================================================

-- Example student insertion
-- Run only when a test student is required.

INSERT INTO student (
    reg_no,
    full_name,
    class,
    date_of_birth,
    gender,
    phone,
    email,
    admin_id,
    house_no,
    city,
    pin
)
VALUES (
    'STU999',
    'Test Student',
    '9 A',
    '2012-05-10',
    'Male',
    '9000000000',
    'test.student@school.com',
    'ADM001',
    '10B',
    'Kollam',
    '691001'
);


-- ============================================================
-- 6. UPDATE
-- ============================================================

-- Example update
UPDATE student
SET phone = '9111111111'
WHERE reg_no = 'STU999';


-- ============================================================
-- 7. DELETE
-- ============================================================

-- Delete the test student
-- Related marks/attendance must be deleted first if they exist.

DELETE FROM student
WHERE reg_no = 'STU999';


-- ============================================================
-- 8. AGGREGATE FUNCTIONS
-- ============================================================

-- Count total students
SELECT COUNT(*) AS total_students
FROM student;

-- Count normalized subject-mark records
SELECT COUNT(*) AS total_marks_records
FROM student_subject_marks;

-- Average mathematics mark
SELECT ROUND(AVG(marks_obtained), 2) AS average_mathematics
FROM student_subject_marks
WHERE subject_id = (
    SELECT subject_id
    FROM subjects
    WHERE subject_code = 'MTH103'
);

-- Highest mathematics mark
SELECT MAX(marks_obtained) AS highest_mathematics
FROM student_subject_marks
WHERE subject_id = (
    SELECT subject_id
    FROM subjects
    WHERE subject_code = 'MTH103'
);

-- Lowest mathematics mark
SELECT MIN(marks_obtained) AS lowest_mathematics
FROM student_subject_marks
WHERE subject_id = (
    SELECT subject_id
    FROM subjects
    WHERE subject_code = 'MTH103'
);


-- ============================================================
-- 9. GROUP BY
-- ============================================================

-- Count students in each class
SELECT
    class,
    COUNT(*) AS student_count
FROM student
GROUP BY class
ORDER BY class;

-- Count students by gender
SELECT
    gender,
    COUNT(*) AS student_count
FROM student
GROUP BY gender;


-- ============================================================
-- 10. INNER JOIN
-- ============================================================

-- Display students and their marks by subject and exam
SELECT
    s.reg_no,
    s.full_name,
    s.class,
    r.exam_type,
    r.academic_year,
    r.attempt_number,
    sub.subject_code,
    sub.subject_name,
    m.marks_obtained
FROM student s
INNER JOIN student_subject_marks m
    ON s.reg_no = m.reg_no
INNER JOIN subjects sub
    ON m.subject_id = sub.subject_id
INNER JOIN report r
    ON r.reg_no = m.reg_no
   AND r.exam_type = m.exam_type
   AND r.academic_year = m.academic_year
   AND r.attempt_number = m.attempt_number
WHERE sub.subject_code IN (
    'FL101', 'SL102', 'MTH103', 'SCI104', 'ART105'
)
ORDER BY
    s.reg_no,
    r.exam_type,
    r.attempt_number,
    sub.subject_code;


-- ============================================================
-- 11. LEFT JOIN
-- ============================================================

-- Display all students and their attendance records
-- Students without attendance records are also included.

SELECT
    s.reg_no,
    s.full_name,
    a.attendance_date,
    a.status
FROM student s
LEFT JOIN attendance a
    ON s.reg_no = a.reg_no
ORDER BY s.reg_no, a.attendance_date;


-- ============================================================
-- 12. MULTI-TABLE JOIN
-- ============================================================

SELECT
    s.reg_no,
    s.full_name,
    s.class,
    r.report_id,
    r.exam_type,
    r.academic_year,
    r.attempt_number,
    sub.subject_code,
    sub.subject_name,
    m.marks_obtained
FROM student s
INNER JOIN report r
    ON s.reg_no = r.reg_no
INNER JOIN student_subject_marks m
    ON r.reg_no = m.reg_no
   AND r.exam_type = m.exam_type
   AND r.academic_year = m.academic_year
   AND r.attempt_number = m.attempt_number
INNER JOIN subjects sub
    ON m.subject_id = sub.subject_id
WHERE sub.subject_code IN (
    'FL101', 'SL102', 'MTH103', 'SCI104', 'ART105'
)
ORDER BY
    r.report_id,
    sub.subject_code;


-- ============================================================
-- 13. SUBQUERY
-- ============================================================

SELECT
    s.reg_no,
    s.full_name,
    m.marks_obtained AS mathematics_mark
FROM student s
INNER JOIN student_subject_marks m
    ON s.reg_no = m.reg_no
INNER JOIN subjects sub
    ON m.subject_id = sub.subject_id
WHERE sub.subject_code = 'MTH103'
  AND m.marks_obtained > (
      SELECT AVG(m2.marks_obtained)
      FROM student_subject_marks m2
      INNER JOIN subjects sub2
          ON m2.subject_id = sub2.subject_id
      WHERE sub2.subject_code = 'MTH103'
  )
ORDER BY m.marks_obtained DESC;


-- ============================================================
-- 14. VIEW
-- ============================================================

-- Display the existing student details view

SELECT *
FROM student_details;

-- Display the existing student reports view

SELECT *
FROM student_reports;


-- ============================================================
-- 15. ATTENDANCE SUMMARY
-- ============================================================

SELECT
    s.reg_no,
    s.full_name,
    a.attendance_type,
    COUNT(a.attend_id) AS total_records,
    COUNT(a.attend_id) FILTER (
        WHERE a.status = 'Present'
    ) AS present_records,
    COUNT(a.attend_id) FILTER (
        WHERE a.status = 'Absent'
    ) AS absent_records
FROM student s
LEFT JOIN attendance a
    ON s.reg_no = a.reg_no
GROUP BY
    s.reg_no,
    s.full_name,
    a.attendance_type
ORDER BY s.reg_no, a.attendance_type;


-- ============================================================
-- 16. ATTENDANCE PERCENTAGE
-- ============================================================

SELECT
    s.reg_no,
    s.full_name,
    a.attendance_type,
    sub.subject_code,
    sub.subject_name,
    COUNT(a.attend_id) AS total_records,
    COUNT(a.attend_id) FILTER (
        WHERE a.status = 'Present'
    ) AS present_records,
    COUNT(a.attend_id) FILTER (
        WHERE a.status = 'Absent'
    ) AS absent_records,
    ROUND(
        100.0 * COUNT(a.attend_id) FILTER (
            WHERE a.status = 'Present'
        ) / NULLIF(COUNT(a.attend_id), 0),
        2
    ) AS attendance_percentage
FROM student s
LEFT JOIN attendance a
    ON s.reg_no = a.reg_no
LEFT JOIN subjects sub
    ON a.subject_id = sub.subject_id
GROUP BY
    s.reg_no,
    s.full_name,
    a.attendance_type,
    sub.subject_code,
    sub.subject_name
ORDER BY
    s.reg_no,
    a.attendance_type,
    sub.subject_code;


-- ============================================================
-- 17. STUDENT SEARCH WITH MULTIPLE CONDITIONS
-- ============================================================

SELECT
    reg_no,
    full_name,
    class,
    gender,
    phone,
    email
FROM student
WHERE class = '10 A'
  AND gender = 'Male'
ORDER BY full_name;


-- ============================================================
-- 18. MARKS SUMMARY
-- ============================================================

SELECT
    report_id,
    reg_no,
    full_name,
    class,
    exam_type,
    academic_year,
    attempt_number,
    first_language,
    second_language,
    mathematics,
    science,
    arts,
    total_marks,
    average,
    grade
FROM student_reports
ORDER BY reg_no, report_id;


-- ============================================================
-- 19. INDEX VERIFICATION
-- ============================================================

SELECT
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
      'student',
      'student_subject_marks',
      'attendance',
      'report',
      'subjects'
  )
ORDER BY tablename, indexname;


-- ============================================================
-- 20. VIEW DEFINITIONS / VERIFICATION
-- ============================================================

-- List available views
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public';


-- ============================================================
-- 21. TEACHER MANAGEMENT & ACTIVE FACULTY
-- ============================================================

-- List all active teachers ordered by name
SELECT teacher_id, full_name, email, phone, qualification, specialization, joining_date
FROM teacher
WHERE status = 'Active'
ORDER BY full_name ASC;


-- ============================================================
-- 22. TEACHER ASSIGNMENTS & CLASS WORKLOAD
-- ============================================================

-- Show teacher assignments with class and subject details
SELECT
    ta.assignment_id,
    t.teacher_id,
    t.full_name AS teacher_name,
    c.class_code,
    c.class_name,
    sub.subject_code,
    sub.subject_name
FROM teacher_assignment ta
INNER JOIN teacher t ON ta.teacher_id = t.teacher_id
INNER JOIN classes c ON ta.class_id = c.class_id
INNER JOIN subjects sub ON ta.subject_id = sub.subject_id
ORDER BY t.full_name, c.class_code;

-- Workload summary: Number of classes, subjects, and weekly periods per teacher
SELECT
    t.teacher_id,
    t.full_name,
    COALESCE(assign_agg.total_classes_taught, 0) AS total_classes_taught,
    COALESCE(assign_agg.total_subjects_taught, 0) AS total_subjects_taught,
    COALESCE(assign_agg.total_assignments, 0) AS total_assignments,
    COALESCE(tt_agg.weekly_periods, 0) AS weekly_periods
FROM teacher t
LEFT JOIN (
    SELECT
        teacher_id,
        COUNT(DISTINCT class_id) AS total_classes_taught,
        COUNT(DISTINCT subject_id) AS total_subjects_taught,
        COUNT(assignment_id) AS total_assignments
    FROM teacher_assignment
    GROUP BY teacher_id
) assign_agg ON t.teacher_id = assign_agg.teacher_id
LEFT JOIN (
    SELECT
        teacher_id,
        COUNT(timetable_id) AS weekly_periods
    FROM timetable
    GROUP BY teacher_id
) tt_agg ON t.teacher_id = tt_agg.teacher_id
ORDER BY total_assignments DESC, t.full_name ASC;


-- ============================================================
-- 23. TIMETABLE SCHEDULE & OVERLAP DETECTION
-- ============================================================

-- View full weekly timetable for a specific class (e.g., '10 A')
SELECT
    tt.timetable_id,
    c.class_code,
    tt.day_of_week,
    tt.start_time,
    tt.end_time,
    sub.subject_name,
    t.full_name AS teacher_name,
    tt.room_number
FROM timetable tt
INNER JOIN classes c ON tt.class_id = c.class_id
INNER JOIN subjects sub ON tt.subject_id = sub.subject_id
INNER JOIN teacher t ON tt.teacher_id = t.teacher_id
WHERE c.class_code = '10 A'
ORDER BY
    CASE tt.day_of_week
        WHEN 'Monday' THEN 1
        WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday' THEN 4
        WHEN 'Friday' THEN 5
        WHEN 'Saturday' THEN 6
        ELSE 7
    END,
    tt.start_time;

-- Check for timetable slot conflicts for a teacher:
-- Two slots overlap if: Day is same AND start_1 < end_2 AND end_1 > start_2
SELECT
    t1.timetable_id AS slot1_id,
    t2.timetable_id AS slot2_id,
    t1.teacher_id,
    t1.day_of_week,
    t1.start_time AS slot1_start,
    t1.end_time AS slot1_end,
    t2.start_time AS slot2_start,
    t2.end_time AS slot2_end
FROM timetable t1
INNER JOIN timetable t2
    ON t1.teacher_id = t2.teacher_id
    AND t1.day_of_week = t2.day_of_week
    AND t1.timetable_id < t2.timetable_id
    AND t1.start_time < t2.end_time
    AND t1.end_time > t2.start_time;


-- ============================================================
-- 24. ANNOUNCEMENTS & TARGET AUDIENCE
-- ============================================================

-- View active announcements applicable to teachers
SELECT announcement_id, title, content, target_audience, priority, created_at
FROM announcements
WHERE is_active = TRUE
  AND target_audience IN ('All', 'Teachers')
ORDER BY
    CASE priority
        WHEN 'Urgent' THEN 1
        WHEN 'High' THEN 2
        WHEN 'Normal' THEN 3
        ELSE 4
    END,
    created_at DESC;


-- ============================================================
-- 25. CLASS PERFORMANCE AGGREGATION
-- ============================================================

SELECT
    class,
    COUNT(*) AS total_exam_records,
    COUNT(DISTINCT reg_no) AS total_students,
    ROUND(AVG(total_marks), 2) AS average_total_marks,
    ROUND(AVG(average), 2) AS class_average,
    MAX(average) AS highest_average,
    MIN(average) AS lowest_average
FROM student_reports
GROUP BY class
ORDER BY class;


-- ============================================================
-- END OF SQL QUERY DEMONSTRATION
-- ============================================================