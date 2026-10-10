const express = require("express");
const router = express.Router();
const bcrypt = require("bcryptjs");
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

// All routes require authentication
router.use(verifyToken);

/**
 * GET /api/teachers
 * Retrieve all teachers (Administrator only)
 */
router.get("/", requireAdmin, async (req, res) => {
  try {
    const { search, status } = req.query;
    let query = `
      SELECT teacher_id, full_name, email, phone, qualification, specialization, joining_date, status, created_at
      FROM teacher
      WHERE 1=1
    `;
    const params = [];

    if (search && search.trim()) {
      params.push(`%${search.trim()}%`);
      query += ` AND (full_name ILIKE $${params.length} OR teacher_id ILIKE $${params.length} OR email ILIKE $${params.length})`;
    }

    if (status && status.trim()) {
      params.push(status.trim());
      query += ` AND status = $${params.length}`;
    }

    query += ` ORDER BY teacher_id ASC`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching teachers:", error);
    res.status(500).json({ message: "Failed to fetch teachers." });
  }
});

/**
 * GET /api/teachers/:teacher_id
 * Retrieve single teacher profile (Admin or the teacher themselves)
 */
router.get("/:teacher_id", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { teacher_id } = req.params;

    // A teacher can only view their own profile unless admin
    if (req.user.role === "teacher" && req.user.id !== teacher_id) {
      return res.status(403).json({ message: "Access forbidden: You can only view your own profile." });
    }

    const result = await pool.query(
      `SELECT teacher_id, full_name, email, phone, qualification, specialization, joining_date, status, created_at
       FROM teacher
       WHERE teacher_id = $1`,
      [teacher_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Teacher not found." });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error("Error fetching teacher profile:", error);
    res.status(500).json({ message: "Failed to fetch teacher profile." });
  }
});

/**
 * POST /api/teachers
 * Add a new teacher (Administrator only)
 */
router.post("/", requireAdmin, async (req, res) => {
  try {
    const {
      teacher_id,
      full_name,
      email,
      phone,
      qualification,
      specialization,
      joining_date,
      password,
      status = "Active",
    } = req.body;

    if (!teacher_id || !full_name || !email || !phone || !password) {
      return res.status(400).json({
        message: "Missing required fields: teacher_id, full_name, email, phone, password are required.",
      });
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ message: "Invalid email format." });
    }

    // Hash password with bcrypt
    const password_hash = await bcrypt.hash(password, 10);

    const result = await pool.query(
      `INSERT INTO teacher (teacher_id, full_name, email, phone, qualification, specialization, joining_date, status, password_hash)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING teacher_id, full_name, email, phone, qualification, specialization, joining_date, status, created_at`,
      [
        teacher_id.trim().toUpperCase(),
        full_name.trim(),
        email.trim().toLowerCase(),
        phone.trim(),
        qualification ? qualification.trim() : null,
        specialization ? specialization.trim() : null,
        joining_date || new Date().toISOString().split("T")[0],
        status,
        password_hash,
      ]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("Error creating teacher:", error);
    if (error.code === "23505") {
      if (error.constraint && error.constraint.includes("email")) {
        return res.status(409).json({ message: "A teacher with this email already exists." });
      }
      return res.status(409).json({ message: "A teacher with this ID already exists." });
    }
    res.status(500).json({ message: "Failed to create teacher account.", error: error.message });
  }
});

/**
 * PUT /api/teachers/:teacher_id
 * Edit teacher details (Administrator only)
 */
router.put("/:teacher_id", requireAdmin, async (req, res) => {
  try {
    const { teacher_id } = req.params;
    const {
      full_name,
      email,
      phone,
      qualification,
      specialization,
      joining_date,
      status,
      password,
    } = req.body;

    let query;
    let params;

    if (password && password.trim()) {
      const password_hash = await bcrypt.hash(password.trim(), 10);
      query = `
        UPDATE teacher
        SET full_name = $1, email = $2, phone = $3, qualification = $4, specialization = $5, joining_date = $6, status = $7, password_hash = $8
        WHERE teacher_id = $9
        RETURNING teacher_id, full_name, email, phone, qualification, specialization, joining_date, status, created_at
      `;
      params = [
        full_name,
        email.trim().toLowerCase(),
        phone,
        qualification,
        specialization,
        joining_date,
        status,
        password_hash,
        teacher_id,
      ];
    } else {
      query = `
        UPDATE teacher
        SET full_name = $1, email = $2, phone = $3, qualification = $4, specialization = $5, joining_date = $6, status = $7
        WHERE teacher_id = $8
        RETURNING teacher_id, full_name, email, phone, qualification, specialization, joining_date, status, created_at
      `;
      params = [
        full_name,
        email.trim().toLowerCase(),
        phone,
        qualification,
        specialization,
        joining_date,
        status,
        teacher_id,
      ];
    }

    const result = await pool.query(query, params);

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Teacher not found." });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error("Error updating teacher:", error);
    if (error.code === "23505") {
      return res.status(409).json({ message: "Email is already in use by another teacher." });
    }
    res.status(500).json({ message: "Failed to update teacher profile.", error: error.message });
  }
});

/**
 * PATCH /api/teachers/:teacher_id/status
 * Deactivate or activate teacher safely (Administrator only)
 */
router.patch("/:teacher_id/status", requireAdmin, async (req, res) => {
  try {
    const { teacher_id } = req.params;
    const { status } = req.body;

    if (!["Active", "Inactive", "Suspended"].includes(status)) {
      return res.status(400).json({ message: "Invalid status value. Must be 'Active', 'Inactive', or 'Suspended'." });
    }

    const result = await pool.query(
      `UPDATE teacher SET status = $1 WHERE teacher_id = $2
       RETURNING teacher_id, full_name, status`,
      [status, teacher_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Teacher not found." });
    }

    res.json({ message: `Teacher status updated to ${status}.`, teacher: result.rows[0] });
  } catch (error) {
    console.error("Error updating teacher status:", error);
    res.status(500).json({ message: "Failed to update teacher status." });
  }
});

/**
 * DELETE /api/teachers/:teacher_id
 * Safely delete teacher account (Administrator only)
 */
router.delete("/:teacher_id", requireAdmin, async (req, res) => {
  try {
    const { teacher_id } = req.params;

    // Check if teacher has existing assignments or scheduled timetable slots
    const [assignmentCheck, timetableCheck] = await Promise.all([
      pool.query("SELECT COUNT(*) FROM teacher_assignment WHERE teacher_id = $1", [teacher_id]),
      pool.query("SELECT COUNT(*) FROM timetable WHERE teacher_id = $1", [teacher_id]),
    ]);

    const assignCount = parseInt(assignmentCheck.rows[0].count, 10);
    const ttCount = parseInt(timetableCheck.rows[0].count, 10);
    if (assignCount > 0 || ttCount > 0) {
      return res.status(400).json({
        message: `Cannot delete teacher: active dependencies exist (${assignCount} class assignment(s), ${ttCount} scheduled timetable period(s)). Remove these assignments and timetable slots first.`,
      });
    }

    const result = await pool.query(
      "DELETE FROM teacher WHERE teacher_id = $1 RETURNING teacher_id, full_name",
      [teacher_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Teacher not found." });
    }

    res.json({ message: "Teacher deleted successfully.", teacher: result.rows[0] });
  } catch (error) {
    console.error("Error deleting teacher:", error);
    res.status(500).json({ message: "Failed to delete teacher.", error: error.message });
  }
});

module.exports = router;
