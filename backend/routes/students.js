const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

// GET all students (Admin views all; Teacher views students in assigned classes)
router.get("/", verifyToken, requireTeacherOrAdmin, async (req, res) => {
  try {
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
      const result = await pool.query(
        `SELECT * FROM student_details WHERE UPPER(TRIM(class)) = ANY(SELECT UPPER(TRIM(unnest($1::text[])))) ORDER BY reg_no`,
        [allAllowed]
      );
      return res.json(result.rows);
    }

    const result = await pool.query(`
      SELECT *
      FROM student_details
      ORDER BY reg_no
    `);

    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching students:", error);
    res.status(500).json({
      message: "Failed to fetch students",
      error: error.message,
    });
  }
});

// POST a new student (Administrator only)
router.post("/", verifyToken, requireAdmin, async (req, res) => {
  try {
    const {
      reg_no,
      full_name,
      class: studentClass,
      date_of_birth,
      gender,
      phone,
      email,
      house_no,
      city,
      pin,
    } = req.body;

    const admin_id = req.body.admin_id || req.user.id || "ADM001";

    const result = await pool.query(
      `
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
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING *;
      `,
      [
        reg_no,
        full_name,
        studentClass,
        date_of_birth,
        gender,
        phone,
        email,
        admin_id,
        house_no,
        city,
        pin,
      ]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("Error adding student:", error);
    res.status(500).json({
      message: "Failed to add student",
      error: error.message,
    });
  }
});

// GET a student by registration number (Admin or authorized Teacher)
router.get("/:reg_no", verifyToken, requireTeacherOrAdmin, async (req, res) => {
  try {
    const { reg_no } = req.params;

    const result = await pool.query(
      `
      SELECT *
      FROM student_details
      WHERE reg_no = $1
      `,
      [reg_no]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "Student not found",
      });
    }

    const student = result.rows[0];

    // If teacher, ensure student belongs to assigned class
    if (req.user.role === "teacher") {
      const authCheck = await pool.query(
        `SELECT 1 FROM teacher_assignment ta
         JOIN classes c ON ta.class_id = c.class_id
         WHERE ta.teacher_id = $1 
           AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM($2))
                OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM($2)))`,
        [req.user.id, student.class]
      );
      if (authCheck.rows.length === 0) {
        return res.status(403).json({ message: "Access forbidden: Student is not in your assigned class." });
      }
    }

    res.json(student);
  } catch (error) {
    console.error("Error fetching student:", error);
    res.status(500).json({
      message: "Failed to fetch student",
      error: error.message,
    });
  }
});

// UPDATE a student (Administrator only)
router.put("/:reg_no", verifyToken, requireAdmin, async (req, res) => {
  try {
    const { reg_no } = req.params;

    const {
      full_name,
      class: studentClass,
      date_of_birth,
      gender,
      phone,
      email,
      house_no,
      city,
      pin,
    } = req.body;

    const admin_id = req.body.admin_id || req.user.id || "ADM001";

    const result = await pool.query(
      `
      UPDATE student
      SET
          full_name = $1,
          class = $2,
          date_of_birth = $3,
          gender = $4,
          phone = $5,
          email = $6,
          admin_id = $7,
          house_no = $8,
          city = $9,
          pin = $10
      WHERE reg_no = $11
      RETURNING *;
      `,
      [
        full_name,
        studentClass,
        date_of_birth,
        gender,
        phone,
        email,
        admin_id,
        house_no,
        city,
        pin,
        reg_no,
      ]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "Student not found",
      });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error("Error updating student:", error);
    res.status(500).json({
      message: "Failed to update student",
      error: error.message,
    });
  }
});

// DELETE a student (Administrator only)
router.delete("/:reg_no", verifyToken, requireAdmin, async (req, res) => {
  try {
    const { reg_no } = req.params;

    // Check dependent records (student_subject_marks, attendance, reports)
    const [marksCount, attCount, reportCount] = await Promise.all([
      pool.query("SELECT COUNT(*) FROM student_subject_marks WHERE reg_no = $1", [reg_no]),
      pool.query("SELECT COUNT(*) FROM attendance WHERE reg_no = $1", [reg_no]),
      pool.query("SELECT COUNT(*) FROM report WHERE reg_no = $1", [reg_no]),
    ]);

    const mCount = parseInt(marksCount.rows[0].count, 10);
    const aCount = parseInt(attCount.rows[0].count, 10);
    const rCount = parseInt(reportCount.rows[0].count, 10);

    if (mCount > 0 || aCount > 0 || rCount > 0) {
      return res.status(400).json({
        message: `Cannot delete student: Dependent academic records exist (${mCount} marks, ${aCount} attendance, ${rCount} reports). Delete those records first.`,
      });
    }

    const result = await pool.query(
      `
      DELETE FROM student
      WHERE reg_no = $1
      RETURNING *;
      `,
      [reg_no]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        message: "Student not found",
      });
    }

    res.json({
      message: "Student deleted successfully",
      student: result.rows[0],
    });
  } catch (error) {
    console.error("Error deleting student:", error);
    res.status(500).json({
      message: "Failed to delete student",
      error: error.message,
    });
  }
});

module.exports = router;
