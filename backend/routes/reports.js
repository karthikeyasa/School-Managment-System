const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireTeacherOrAdmin, requireAdmin } = require("../middleware/auth");

router.use(verifyToken);

// GET all student reports
router.get("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    let query = `
      SELECT sr.*, s.class
      FROM student_reports sr
      JOIN student s ON sr.reg_no = s.reg_no
    `;
    const params = [];

    if (req.user.role === "teacher") {
      const authClasses = await pool.query(
        `SELECT DISTINCT c.class_code, (c.class_name || ' ' || c.section) AS alt_code
         FROM teacher_assignment ta 
         JOIN classes c ON ta.class_id = c.class_id 
         WHERE ta.teacher_id = $1`,
        [req.user.id]
      );
      const codes = authClasses.rows.map((r) => r.class_code);
      const altCodes = authClasses.rows.map((r) => r.alt_code).filter(Boolean);
      const allAllowed = [...new Set([...codes, ...altCodes])];

      if (allAllowed.length === 0) {
        return res.json([]);
      }
      query += ` WHERE UPPER(TRIM(s.class)) = ANY(SELECT UPPER(TRIM(unnest($1::text[]))))`;
      params.push(allAllowed);
    }

    query += ` ORDER BY sr.reg_no, sr.report_id`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching reports:", error);
    res.status(500).json({
      message: "Failed to fetch reports",
      error: error.message,
    });
  }
});

// GET reports for a specific class (Pivoted from normalized schema with 5 core subjects)
router.get("/class-performance/:class_code", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { class_code } = req.params;

    if (req.user.role === "teacher") {
      const authCheck = await pool.query(
        `SELECT 1 FROM teacher_assignment ta
         JOIN classes c ON ta.class_id = c.class_id
         WHERE ta.teacher_id = $1 
           AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM($2))
                OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM($2)))`,
        [req.user.id, class_code]
      );
      if (authCheck.rows.length === 0) {
        return res.status(403).json({ message: "Access forbidden: You are not assigned to this class." });
      }
    }

    const result = await pool.query(
      `SELECT 
        sr.report_id,
        sr.reg_no,
        sr.full_name,
        sr.class,
        sr.exam_type,
        sr.academic_year,
        sr.attempt_number,
        sr.first_language,
        sr.second_language,
        sr.mathematics,
        sr.science,
        sr.arts,
        sr.total_marks,
        sr.average,
        sr.grade
      FROM student_reports sr
      WHERE UPPER(TRIM(sr.class)) = UPPER(TRIM($1))
      ORDER BY sr.reg_no, sr.exam_type, sr.attempt_number`,
      [class_code]
    );

    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching class performance report:", error);
    res.status(500).json({ message: "Failed to fetch class performance report." });
  }
});

// GET attendance summary for a specific class
router.get("/class-attendance/:class_code", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { class_code } = req.params;

    if (req.user.role === "teacher") {
      const authCheck = await pool.query(
        `SELECT 1 FROM teacher_assignment ta
         JOIN classes c ON ta.class_id = c.class_id
         WHERE ta.teacher_id = $1 
           AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM($2))
                OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM($2)))`,
        [req.user.id, class_code]
      );
      if (authCheck.rows.length === 0) {
        return res.status(403).json({ message: "Access forbidden: You are not assigned to this class." });
      }
    }

    const result = await pool.query(
      `SELECT
        s.reg_no,
        s.full_name,
        s.class,
        COUNT(a.attend_id) AS total_days,
        COUNT(*) FILTER (WHERE a.status = 'Present') AS present_days,
        COUNT(*) FILTER (WHERE a.status = 'Absent') AS absent_days,
        ROUND((COUNT(*) FILTER (WHERE a.status = 'Present')::numeric / NULLIF(COUNT(a.attend_id), 0)) * 100, 2) AS attendance_percentage
      FROM student s
      LEFT JOIN attendance a ON s.reg_no = a.reg_no
      WHERE UPPER(TRIM(s.class)) = UPPER(TRIM($1))
      GROUP BY s.reg_no, s.full_name, s.class
      ORDER BY s.reg_no`,
      [class_code]
    );

    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching class attendance report:", error);
    res.status(500).json({ message: "Failed to fetch class attendance report." });
  }
});

// GET teacher assignments and workload report (Admin only)
router.get("/teacher-workloads", requireAdmin, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT 
        t.teacher_id,
        t.full_name,
        t.email,
        t.specialization,
        COALESCE(assign_agg.total_classes_taught, 0)::integer AS total_classes_taught,
        COALESCE(assign_agg.total_subjects_taught, 0)::integer AS total_subjects_taught,
        COALESCE(assign_agg.total_assignments, 0)::integer AS total_assignments,
        COALESCE(tt_agg.weekly_periods, 0)::integer AS weekly_periods
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
      WHERE t.status = 'Active'
      ORDER BY total_assignments DESC, t.full_name ASC
    `);

    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching teacher workloads:", error);
    res.status(500).json({ message: "Failed to fetch teacher workload report." });
  }
});

// GET reports for a specific student
router.get("/:reg_no", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { reg_no } = req.params;

    if (req.user.role === "teacher") {
      const studentRes = await pool.query("SELECT class FROM student WHERE reg_no = $1", [reg_no]);
      if (studentRes.rows.length === 0) {
        return res.status(404).json({ message: "Student not found" });
      }
      const authCheck = await pool.query(
        `SELECT 1 FROM teacher_assignment ta
         JOIN classes c ON ta.class_id = c.class_id
         WHERE ta.teacher_id = $1 
           AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM($2))
                OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM($2)))`,
        [req.user.id, studentRes.rows[0].class]
      );
      if (authCheck.rows.length === 0) {
        return res.status(403).json({ message: "Access forbidden: Student is not in your assigned class." });
      }
    }

    const result = await pool.query(
      `
      SELECT *
      FROM student_reports
      WHERE reg_no = $1
      ORDER BY report_id
      `,
      [reg_no]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "No reports found for this student",
      });
    }

    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching student reports:", error);
    res.status(500).json({
      message: "Failed to fetch student reports",
      error: error.message,
    });
  }
});

module.exports = router;
