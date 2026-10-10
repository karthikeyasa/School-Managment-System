const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

router.use(verifyToken);

/**
 * GET /api/subjects
 * List all subjects (Admin & Teachers)
 */
router.get("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT subject_id, subject_code, subject_name, department
      FROM subjects
      ORDER BY subject_id ASC
    `);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching subjects:", error);
    res.status(500).json({ message: "Failed to fetch subjects." });
  }
});

/**
 * POST /api/subjects
 * Add new subject (Admin only)
 */
router.post("/", requireAdmin, async (req, res) => {
  try {
    const { subject_code, subject_name, department } = req.body;

    if (!subject_code || !subject_name) {
      return res.status(400).json({ message: "Subject code and subject name are required." });
    }

    const result = await pool.query(
      `INSERT INTO subjects (subject_code, subject_name, department)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [subject_code.trim().toUpperCase(), subject_name.trim(), department ? department.trim() : null]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("Error creating subject:", error);
    if (error.code === "23505") {
      return res.status(409).json({ message: "A subject with this subject code already exists." });
    }
    res.status(500).json({ message: "Failed to create subject.", error: error.message });
  }
});

/**
 * PUT /api/subjects/:subject_id
 * Update subject (Admin only)
 */
router.put("/:subject_id", requireAdmin, async (req, res) => {
  try {
    const { subject_id } = req.params;
    const { subject_code, subject_name, department } = req.body;

    const result = await pool.query(
      `UPDATE subjects
       SET subject_code = $1, subject_name = $2, department = $3
       WHERE subject_id = $4
       RETURNING *`,
      [subject_code.trim().toUpperCase(), subject_name.trim(), department, subject_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Subject not found." });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error("Error updating subject:", error);
    res.status(500).json({ message: "Failed to update subject.", error: error.message });
  }
});

/**
 * DELETE /api/subjects/:subject_id
 * Delete subject (Admin only)
 */
router.delete("/:subject_id", requireAdmin, async (req, res) => {
  try {
    const { subject_id } = req.params;

    const [assignmentCheck, timetableCheck] = await Promise.all([
      pool.query("SELECT COUNT(*) FROM teacher_assignment WHERE subject_id = $1", [subject_id]),
      pool.query("SELECT COUNT(*) FROM timetable WHERE subject_id = $1", [subject_id]),
    ]);

    const assignCount = parseInt(assignmentCheck.rows[0].count, 10);
    const ttCount = parseInt(timetableCheck.rows[0].count, 10);

    if (assignCount > 0 || ttCount > 0) {
      return res.status(400).json({
        message: `Cannot delete subject: active dependencies exist (${assignCount} teacher assignment(s), ${ttCount} scheduled timetable period(s)). Remove these assignments and timetable slots first.`,
      });
    }

    const result = await pool.query("DELETE FROM subjects WHERE subject_id = $1 RETURNING *", [subject_id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Subject not found." });
    }

    res.json({ message: "Subject deleted successfully.", subject: result.rows[0] });
  } catch (error) {
    console.error("Error deleting subject:", error);
    res.status(500).json({ message: "Failed to delete subject.", error: error.message });
  }
});

module.exports = router;
