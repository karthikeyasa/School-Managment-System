const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

router.use(verifyToken);

/**
 * GET /api/assignments
 * List all assignments (Admin only)
 */
router.get("/", requireAdmin, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT 
        ta.assignment_id,
        ta.teacher_id,
        t.full_name AS teacher_name,
        t.email AS teacher_email,
        ta.class_id,
        c.class_name,
        c.section,
        c.class_code,
        ta.subject_id,
        s.subject_code,
        s.subject_name,
        ta.academic_year,
        ta.assigned_date
      FROM teacher_assignment ta
      JOIN teacher t ON ta.teacher_id = t.teacher_id
      JOIN classes c ON ta.class_id = c.class_id
      JOIN subjects s ON ta.subject_id = s.subject_id
      ORDER BY c.class_name, c.section, s.subject_name
    `);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching assignments:", error);
    res.status(500).json({ message: "Failed to fetch teacher assignments." });
  }
});

/**
 * GET /api/assignments/teacher/:teacher_id
 * Get assignments for specific teacher (Admin or assigned teacher)
 */
router.get("/teacher/:teacher_id", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { teacher_id } = req.params;

    if (req.user.role === "teacher" && req.user.id !== teacher_id) {
      return res.status(403).json({ message: "Forbidden: You can only view your own assignments." });
    }

    const result = await pool.query(
      `SELECT 
        ta.assignment_id,
        ta.teacher_id,
        t.full_name AS teacher_name,
        ta.class_id,
        c.class_name,
        c.section,
        c.class_code,
        ta.subject_id,
        s.subject_code,
        s.subject_name,
        ta.academic_year,
        ta.assigned_date
      FROM teacher_assignment ta
      JOIN teacher t ON ta.teacher_id = t.teacher_id
      JOIN classes c ON ta.class_id = c.class_id
      JOIN subjects s ON ta.subject_id = s.subject_id
      WHERE ta.teacher_id = $1
      ORDER BY c.class_name, c.section, s.subject_name`,
      [teacher_id]
    );

    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching teacher assignments:", error);
    res.status(500).json({ message: "Failed to fetch teacher assignments." });
  }
});

/**
 * POST /api/assignments
 * Create assignment (Admin only)
 */
router.post("/", requireAdmin, async (req, res) => {
  try {
    const { teacher_id, class_id, subject_id, academic_year = "2026-2027" } = req.body;

    if (!teacher_id || !class_id || !subject_id) {
      return res.status(400).json({ message: "teacher_id, class_id, and subject_id are required." });
    }

    // Verify teacher exists and is active
    const teacherCheck = await pool.query("SELECT status FROM teacher WHERE teacher_id = $1", [teacher_id]);
    if (teacherCheck.rows.length === 0) {
      return res.status(404).json({ message: "Teacher not found." });
    }
    if (teacherCheck.rows[0].status !== "Active") {
      return res.status(400).json({ message: "Cannot assign inactive teacher." });
    }

    // Verify class exists
    const classCheck = await pool.query("SELECT class_id FROM classes WHERE class_id = $1", [class_id]);
    if (classCheck.rows.length === 0) {
      return res.status(404).json({ message: "Class not found." });
    }

    // Verify subject exists
    const subjectCheck = await pool.query("SELECT subject_id FROM subjects WHERE subject_id = $1", [subject_id]);
    if (subjectCheck.rows.length === 0) {
      return res.status(404).json({ message: "Subject not found." });
    }

    const result = await pool.query(
      `INSERT INTO teacher_assignment (teacher_id, class_id, subject_id, academic_year)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [teacher_id, class_id, subject_id, academic_year]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("Error creating assignment:", error);
    if (error.code === "23505") {
      return res.status(409).json({ message: "This teacher is already assigned to this class and subject for this academic year." });
    }
    res.status(500).json({ message: "Failed to assign teacher.", error: error.message });
  }
});

/**
 * DELETE /api/assignments/:assignment_id
 * Remove assignment (Admin only)
 */
router.delete("/:assignment_id", requireAdmin, async (req, res) => {
  try {
    const { assignment_id } = req.params;

    const result = await pool.query("DELETE FROM teacher_assignment WHERE assignment_id = $1 RETURNING *", [
      assignment_id,
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Assignment not found." });
    }

    res.json({ message: "Assignment removed successfully.", assignment: result.rows[0] });
  } catch (error) {
    console.error("Error removing assignment:", error);
    res.status(500).json({ message: "Failed to remove assignment." });
  }
});

module.exports = router;
