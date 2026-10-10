const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

router.use(verifyToken);

/**
 * GET /api/classes
 * List all classes with student count (Teachers and Admins)
 */
router.get("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT 
        c.class_id, 
        c.class_name, 
        c.section, 
        c.academic_year, 
        c.class_code,
        COUNT(s.reg_no) AS student_count
      FROM classes c
      LEFT JOIN student s ON (s.class = c.class_code OR s.class = (c.class_name || ' ' || c.section))
      GROUP BY c.class_id, c.class_name, c.section, c.academic_year, c.class_code
      ORDER BY c.class_name, c.section
    `);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching classes:", error);
    res.status(500).json({ message: "Failed to fetch classes." });
  }
});

/**
 * POST /api/classes
 * Add new class (Admin only)
 */
router.post("/", requireAdmin, async (req, res) => {
  try {
    const { class_name, section, academic_year = "2026-2027" } = req.body;

    if (!class_name || !section) {
      return res.status(400).json({ message: "Class name and section are required." });
    }

    const cleanName = class_name.trim();
    const cleanSection = section.trim().toUpperCase();
    const class_code = `${cleanName} ${cleanSection}`;

    const result = await pool.query(
      `INSERT INTO classes (class_name, section, academic_year, class_code)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [cleanName, cleanSection, academic_year.trim(), class_code]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("Error adding class:", error);
    if (error.code === "23505") {
      return res.status(409).json({ message: "This class and section already exists." });
    }
    res.status(500).json({ message: "Failed to create class.", error: error.message });
  }
});

/**
 * PUT /api/classes/:class_id
 * Update class details (Admin only)
 */
router.put("/:class_id", requireAdmin, async (req, res) => {
  try {
    const { class_id } = req.params;
    const { class_name, section, academic_year } = req.body;

    const cleanName = class_name.trim();
    const cleanSection = section.trim().toUpperCase();
    const class_code = `${cleanName} ${cleanSection}`;

    const result = await pool.query(
      `UPDATE classes 
       SET class_name = $1, section = $2, academic_year = $3, class_code = $4
       WHERE class_id = $5
       RETURNING *`,
      [cleanName, cleanSection, academic_year, class_code, class_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Class not found." });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error("Error updating class:", error);
    res.status(500).json({ message: "Failed to update class.", error: error.message });
  }
});

/**
 * DELETE /api/classes/:class_id
 * Delete class safely (Admin only)
 */
router.delete("/:class_id", requireAdmin, async (req, res) => {
  try {
    const { class_id } = req.params;

    // Check if class has assignments or students
    const classRow = await pool.query("SELECT class_code FROM classes WHERE class_id = $1", [class_id]);
    if (classRow.rows.length === 0) {
      return res.status(404).json({ message: "Class not found." });
    }

    const classCode = classRow.rows[0].class_code;
    const [studentCheck, assignmentCheck, timetableCheck] = await Promise.all([
      pool.query("SELECT COUNT(*) FROM student WHERE UPPER(TRIM(class)) = UPPER(TRIM($1))", [classCode]),
      pool.query("SELECT COUNT(*) FROM teacher_assignment WHERE class_id = $1", [class_id]),
      pool.query("SELECT COUNT(*) FROM timetable WHERE class_id = $1", [class_id]),
    ]);

    const studCount = parseInt(studentCheck.rows[0].count, 10);
    const assignCount = parseInt(assignmentCheck.rows[0].count, 10);
    const ttCount = parseInt(timetableCheck.rows[0].count, 10);

    if (studCount > 0 || assignCount > 0 || ttCount > 0) {
      return res.status(400).json({
        message: `Cannot delete class: active dependencies exist (${studCount} enrolled student(s), ${assignCount} teacher assignment(s), ${ttCount} scheduled timetable slot(s)). Remove dependencies first.`,
      });
    }

    const result = await pool.query("DELETE FROM classes WHERE class_id = $1 RETURNING *", [class_id]);
    res.json({ message: "Class deleted successfully.", class: result.rows[0] });
  } catch (error) {
    console.error("Error deleting class:", error);
    res.status(500).json({ message: "Failed to delete class.", error: error.message });
  }
});

module.exports = router;
