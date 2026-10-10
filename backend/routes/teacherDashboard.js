const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireTeacher } = require("../middleware/auth");

router.use(verifyToken);
router.use(requireTeacher);

/**
 * GET /api/teacher-dashboard/overview
 * Comprehensive dashboard data for the authenticated teacher
 */
router.get("/overview", async (req, res) => {
  try {
    const teacherId = req.user.id;

    // 1. Teacher Profile
    const profileResult = await pool.query(
      `SELECT teacher_id, full_name, email, phone, qualification, specialization, joining_date, status
       FROM teacher
       WHERE teacher_id = $1`,
      [teacherId]
    );

    if (profileResult.rows.length === 0) {
      return res.status(404).json({ message: "Teacher record not found." });
    }

    const profile = profileResult.rows[0];

    // 2. Assigned Classes and Subjects
    const assignmentsResult = await pool.query(
      `SELECT 
        ta.assignment_id,
        ta.class_id,
        c.class_name,
        c.section,
        c.class_code,
        ta.subject_id,
        s.subject_code,
        s.subject_name
       FROM teacher_assignment ta
       JOIN classes c ON ta.class_id = c.class_id
       JOIN subjects s ON ta.subject_id = s.subject_id
       WHERE ta.teacher_id = $1
       ORDER BY c.class_name, c.section, s.subject_name`,
      [teacherId]
    );

    const assignments = assignmentsResult.rows;

    // Extract unique class codes assigned to this teacher
    const assignedClassCodes = [...new Set(assignments.map((a) => a.class_code))];

    // 3. Student Count in Authorized Classes
    let studentCount = 0;
    if (assignedClassCodes.length > 0) {
      const studentCountResult = await pool.query(
        `SELECT COUNT(*) FROM student WHERE UPPER(TRIM(class)) = ANY(SELECT UPPER(TRIM(unnest($1::text[]))))`,
        [assignedClassCodes]
      );
      studentCount = parseInt(studentCountResult.rows[0].count, 10);
    }

    // 4. Today's Attendance in Authorized Classes
    let todayAttendance = { total_recorded: 0, present: 0, absent: 0 };
    if (assignedClassCodes.length > 0) {
      const attResult = await pool.query(
        `SELECT 
          COUNT(a.attend_id) AS total_recorded,
          COUNT(*) FILTER (WHERE a.status = 'Present') AS present,
          COUNT(*) FILTER (WHERE a.status = 'Absent') AS absent
         FROM attendance a
         JOIN student s ON a.reg_no = s.reg_no
         WHERE UPPER(TRIM(s.class)) = ANY(SELECT UPPER(TRIM(unnest($1::text[])))) AND a.attendance_date = CURRENT_DATE`,
        [assignedClassCodes]
      );
      if (attResult.rows.length > 0) {
        todayAttendance = {
          total_recorded: parseInt(attResult.rows[0].total_recorded, 10),
          present: parseInt(attResult.rows[0].present, 10),
          absent: parseInt(attResult.rows[0].absent, 10),
        };
      }
    }

    // 5. Timetable for Today
    const todayName = new Date().toLocaleDateString("en-US", { weekday: "long" });
    const todayTimetableResult = await pool.query(
      `SELECT 
        tt.timetable_id,
        c.class_code,
        s.subject_name,
        TO_CHAR(tt.start_time, 'HH24:MI') AS start_time,
        TO_CHAR(tt.end_time, 'HH24:MI') AS end_time,
        tt.room_number
       FROM timetable tt
       JOIN classes c ON tt.class_id = c.class_id
       JOIN subjects s ON tt.subject_id = s.subject_id
       WHERE tt.teacher_id = $1 AND tt.day_of_week = $2
       ORDER BY tt.start_time ASC`,
      [teacherId, todayName]
    );

    // 6. Recent Active Announcements
    const announcementsResult = await pool.query(
      `SELECT announcement_id, title, content, created_by, created_at
       FROM announcements
       WHERE is_active = TRUE AND (target_audience = 'All' OR target_audience = 'Teachers')
       ORDER BY created_at DESC
       LIMIT 5`
    );

    res.json({
      profile,
      assignments,
      assignedClassCodes,
      studentCount,
      todayAttendance,
      todaySchedule: todayTimetableResult.rows,
      announcements: announcementsResult.rows,
    });
  } catch (error) {
    console.error("Error in teacher overview:", error);
    res.status(500).json({ message: "Failed to load teacher dashboard." });
  }
});

/**
 * GET /api/teacher-dashboard/students
 * Retrieve students ONLY in authorized classes for this teacher
 */
router.get("/students", async (req, res) => {
  try {
    const teacherId = req.user.id;
    const { class_code } = req.query;

    // Get list of authorized class codes for this teacher
    const authClasses = await pool.query(
      `SELECT DISTINCT c.class_code
       FROM teacher_assignment ta
       JOIN classes c ON ta.class_id = c.class_id
       WHERE ta.teacher_id = $1`,
      [teacherId]
    );

    const authorizedClassCodes = authClasses.rows.map((r) => r.class_code);

    if (authorizedClassCodes.length === 0) {
      return res.json([]);
    }

    let query = `
      SELECT reg_no, full_name, class, gender, phone, email
      FROM student
      WHERE UPPER(TRIM(class)) = ANY(SELECT UPPER(TRIM(unnest($1::text[]))))
    `;
    const params = [authorizedClassCodes];

    if (class_code && class_code.trim()) {
      const match = authorizedClassCodes.find(
        (c) => c.toUpperCase().trim() === class_code.trim().toUpperCase()
      );
      if (!match) {
        return res.status(403).json({ message: "Access forbidden: You are not assigned to this class." });
      }
      query += ` AND UPPER(TRIM(class)) = UPPER(TRIM($2))`;
      params.push(class_code.trim());
    }

    query += ` ORDER BY class, reg_no`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching authorized students:", error);
    res.status(500).json({ message: "Failed to load student roster." });
  }
});

module.exports = router;
