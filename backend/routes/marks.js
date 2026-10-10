const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

router.use(verifyToken);

// Map of legacy subject column names to standard subject codes (5 core subjects)
const legacyColToCode = {
  first_language: "FL101",
  second_language: "SL102",
  mathematics: "MTH103",
  science: "SCI104",
  arts: "ART105",
};

/**
 * Helper to resolve subject_id from either numeric ID or subject code string
 */
async function resolveSubjectId(subjectIdent) {
  if (!subjectIdent) return null;
  if (typeof subjectIdent === "number" || /^\d+$/.test(subjectIdent)) {
    const res = await pool.query("SELECT subject_id, subject_code, subject_name FROM subjects WHERE subject_id = $1", [
      parseInt(subjectIdent, 10),
    ]);
    return res.rows[0] || null;
  }
  const clean = String(subjectIdent).trim().toUpperCase();
  const res = await pool.query(
    "SELECT subject_id, subject_code, subject_name FROM subjects WHERE UPPER(subject_code) = $1 OR UPPER(subject_name) = $1",
    [clean]
  );
  return res.rows[0] || null;
}

/**
 * Helper to verify teacher authorization for a student and subject
 */
async function verifyTeacherAssignment(teacherId, studentClass, subjectId) {
  const res = await pool.query(
    `SELECT ta.assignment_id 
     FROM teacher_assignment ta
     JOIN classes c ON ta.class_id = c.class_id
     WHERE ta.teacher_id = $1 
       AND ta.subject_id = $2 
       AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM($3)) 
            OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM($3)))`,
    [teacherId, subjectId, studentClass]
  );
  return res.rows.length > 0;
}

/**
 * GET /api/marks
 * List marks.
 * - Admin: all marks across all students and subjects.
 * - Teacher: strictly marks for students in classes and subjects assigned to this teacher.
 */
router.get("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    let query = `
      SELECT
          m.mark_record_id,
          m.reg_no,
          s.full_name,
          s.class,
          m.subject_id,
          sub.subject_code,
          sub.subject_name,
          m.exam_type,
          m.academic_year,
          m.attempt_number,
          m.marks_obtained,
          m.recorded_by,
          m.created_at,
          m.updated_at
      FROM student_subject_marks m
      JOIN student s ON m.reg_no = s.reg_no
      JOIN subjects sub ON m.subject_id = sub.subject_id
    `;
    const params = [];

    if (req.user.role === "teacher") {
      query += `
        JOIN classes c ON (UPPER(TRIM(c.class_code)) = UPPER(TRIM(s.class)) 
                           OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM(s.class)))
        JOIN teacher_assignment ta 
          ON ta.class_id = c.class_id 
         AND ta.subject_id = m.subject_id 
         AND ta.teacher_id = $1
      `;
      params.push(req.user.id);
    }

    query += ` ORDER BY s.class, m.reg_no, m.exam_type, sub.subject_code`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching marks:", error);
    res.status(500).json({ message: "Failed to fetch marks" });
  }
});

/**
 * GET /api/marks/:reg_no
 * Retrieve marks for a specific student.
 * - Admin: all subjects.
 * - Teacher: strictly assigned subjects.
 */
router.get("/:reg_no", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { reg_no } = req.params;

    const studentRes = await pool.query("SELECT reg_no, full_name, class FROM student WHERE reg_no = $1", [reg_no]);
    if (studentRes.rows.length === 0) {
      return res.status(404).json({ message: "Student not found" });
    }
    const student = studentRes.rows[0];

    let query = `
      SELECT
          m.mark_record_id,
          m.reg_no,
          s.full_name,
          s.class,
          m.subject_id,
          sub.subject_code,
          sub.subject_name,
          m.exam_type,
          m.academic_year,
          m.attempt_number,
          m.marks_obtained,
          m.recorded_by,
          m.created_at,
          m.updated_at
      FROM student_subject_marks m
      JOIN student s ON m.reg_no = s.reg_no
      JOIN subjects sub ON m.subject_id = sub.subject_id
      WHERE m.reg_no = $1
    `;
    const params = [reg_no];

    if (req.user.role === "teacher") {
      query += `
        AND m.subject_id IN (
          SELECT ta.subject_id 
          FROM teacher_assignment ta
          JOIN classes c ON ta.class_id = c.class_id
          WHERE ta.teacher_id = $2 
            AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM($3)) 
                 OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM($3)))
        )
      `;
      params.push(req.user.id, student.class);
    }

    query += ` ORDER BY m.exam_type, sub.subject_code`;

    const result = await pool.query(query, params);

    // Also return backward-compatible pivoted map if client expects it
    const summary = {
      reg_no: student.reg_no,
      full_name: student.full_name,
      class: student.class,
      records: result.rows,
    };

    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching student marks:", error);
    res.status(500).json({ message: "Failed to fetch student marks" });
  }
});

/**
 * POST /api/marks
 * Record or update marks.
 * Supports:
 *   1) Normalized single-subject payload: { reg_no, subject_id, exam_type, marks_obtained, academic_year, attempt_number }
 *   2) Batch/Legacy multi-subject payload: { reg_no, exam_type, first_language, second_language, mathematics, science, arts }
 * Teacher authorization is rigorously validated on every subject modified.
 */
router.post("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    const {
      reg_no,
      exam_type,
      subject_id: rawSubjectId,
      subject_code: rawSubjectCode,
      marks_obtained,
      academic_year = "2026-2027",
      attempt_number = 1,
    } = req.body;

    if (!reg_no || !exam_type) {
      return res.status(400).json({ message: "Student registration number and exam type are required." });
    }

    const studentRes = await pool.query("SELECT reg_no, full_name, class FROM student WHERE reg_no = $1", [reg_no]);
    if (studentRes.rows.length === 0) {
      return res.status(404).json({ message: "Student not found." });
    }
    const student = studentRes.rows[0];

    // Case 1: Normalized single subject submission
    if (rawSubjectId !== undefined || rawSubjectCode !== undefined || marks_obtained !== undefined) {
      if (marks_obtained === undefined || marks_obtained === null || marks_obtained === "") {
        return res.status(400).json({ message: "Marks obtained score is required." });
      }

      const scoreNum = Number(marks_obtained);
      if (isNaN(scoreNum) || scoreNum < 0 || scoreNum > 100) {
        return res.status(400).json({ message: "Marks obtained must be a number between 0 and 100." });
      }

      const subject = await resolveSubjectId(rawSubjectId || rawSubjectCode);
      if (!subject) {
        return res.status(404).json({ message: "Invalid subject specified." });
      }

      // Teacher authorization: must teach this subject in this student's class
      if (req.user.role === "teacher") {
        const isAssigned = await verifyTeacherAssignment(req.user.id, student.class, subject.subject_id);
        if (!isAssigned) {
          return res.status(403).json({
            message: `Access forbidden: You are not assigned to teach ${subject.subject_name} in Class ${student.class}.`,
          });
        }
      }

      const recordedBy = req.user.role === "teacher" ? req.user.id : null;
      const insertRes = await pool.query(
        `INSERT INTO student_subject_marks (
            reg_no, subject_id, exam_type, academic_year, attempt_number, marks_obtained, recorded_by, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)
         ON CONFLICT (reg_no, subject_id, exam_type, academic_year, attempt_number)
         DO UPDATE SET
            marks_obtained = EXCLUDED.marks_obtained,
            recorded_by = EXCLUDED.recorded_by,
            updated_at = CURRENT_TIMESTAMP
         RETURNING *`,
        [reg_no, subject.subject_id, exam_type.trim(), academic_year, parseInt(attempt_number, 10) || 1, scoreNum, recordedBy]
      );

      // Ensure corresponding report entity exists
      await pool.query(
        `INSERT INTO report (reg_no, exam_type, academic_year, attempt_number)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (reg_no, exam_type, academic_year, attempt_number) DO NOTHING`,
        [reg_no, exam_type.trim(), academic_year, parseInt(attempt_number, 10) || 1]
      );

      return res.status(201).json(insertRes.rows[0]);
    }

    // Case 2: Batch submission across core subjects (e.g. from comprehensive entry forms)
    const subjectEntries = [];
    for (const [colName, subCode] of Object.entries(legacyColToCode)) {
      if (req.body[colName] !== undefined && req.body[colName] !== null && req.body[colName] !== "") {
        const score = Number(req.body[colName]);
        if (isNaN(score) || score < 0 || score > 100) {
          return res.status(400).json({ message: `Score for ${colName} must be between 0 and 100.` });
        }
        const sub = await resolveSubjectId(subCode);
        if (sub) {
          subjectEntries.push({ subject: sub, score });
        }
      }
    }

    if (subjectEntries.length === 0) {
      return res.status(400).json({ message: "At least one subject mark must be provided." });
    }

    // Teacher authorization: verify each subject entry
    if (req.user.role === "teacher") {
      for (const entry of subjectEntries) {
        const isAssigned = await verifyTeacherAssignment(req.user.id, student.class, entry.subject.subject_id);
        if (!isAssigned) {
          return res.status(403).json({
            message: `Access forbidden: You are not assigned to teach ${entry.subject.subject_name} in Class ${student.class}.`,
          });
        }
      }
    }

    const savedRecords = [];
    const recordedBy = req.user.role === "teacher" ? req.user.id : null;
    for (const entry of subjectEntries) {
      const upRes = await pool.query(
        `INSERT INTO student_subject_marks (
            reg_no, subject_id, exam_type, academic_year, attempt_number, marks_obtained, recorded_by, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)
         ON CONFLICT (reg_no, subject_id, exam_type, academic_year, attempt_number)
         DO UPDATE SET
            marks_obtained = EXCLUDED.marks_obtained,
            recorded_by = EXCLUDED.recorded_by,
            updated_at = CURRENT_TIMESTAMP
         RETURNING *`,
        [reg_no, entry.subject.subject_id, exam_type.trim(), academic_year, parseInt(attempt_number, 10) || 1, entry.score, recordedBy]
      );
      savedRecords.push(upRes.rows[0]);
    }

    // Ensure corresponding report entity exists
    await pool.query(
      `INSERT INTO report (reg_no, exam_type, academic_year, attempt_number)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (reg_no, exam_type, academic_year, attempt_number) DO NOTHING`,
      [reg_no, exam_type.trim(), academic_year, parseInt(attempt_number, 10) || 1]
    );

    res.status(201).json({
      message: `Marks recorded successfully for ${savedRecords.length} subject(s).`,
      records: savedRecords,
    });
  } catch (error) {
    console.error("Error adding marks:", error);
    res.status(500).json({ message: "Failed to add marks", error: error.message });
  }
});

/**
 * PUT /api/marks/:mark_record_id
 * Update an existing mark record.
 * Teachers can only update mark records for subjects and classes assigned to them.
 */
router.put("/:mark_record_id", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { mark_record_id } = req.params;
    const { marks_obtained, exam_type, attempt_number } = req.body;

    const existingRes = await pool.query(
      `SELECT m.*, s.class, sub.subject_name 
       FROM student_subject_marks m
       JOIN student s ON m.reg_no = s.reg_no
       JOIN subjects sub ON m.subject_id = sub.subject_id
       WHERE m.mark_record_id = $1`,
      [mark_record_id]
    );

    if (existingRes.rows.length === 0) {
      return res.status(404).json({ message: "Marks record not found." });
    }
    const current = existingRes.rows[0];

    // Teacher authorization
    if (req.user.role === "teacher") {
      const isAssigned = await verifyTeacherAssignment(req.user.id, current.class, current.subject_id);
      if (!isAssigned) {
        return res.status(403).json({
          message: `Access forbidden: You are not assigned to teach ${current.subject_name} in Class ${current.class}.`,
        });
      }
    }

    let newScore = current.marks_obtained;
    if (marks_obtained !== undefined) {
      newScore = Number(marks_obtained);
      if (isNaN(newScore) || newScore < 0 || newScore > 100) {
        return res.status(400).json({ message: "Marks obtained must be between 0 and 100." });
      }
    }

    const recordedBy = req.user.role === "teacher" ? req.user.id : null;
    const updateRes = await pool.query(
      `UPDATE student_subject_marks
       SET marks_obtained = $1,
           exam_type = COALESCE($2, exam_type),
           attempt_number = COALESCE($3, attempt_number),
           recorded_by = COALESCE($4, recorded_by),
           updated_at = CURRENT_TIMESTAMP
       WHERE mark_record_id = $5
       RETURNING *`,
      [newScore, exam_type ? exam_type.trim() : null, attempt_number ? parseInt(attempt_number, 10) : null, recordedBy, mark_record_id]
    );

    res.json(updateRes.rows[0]);
  } catch (error) {
    console.error("Error updating marks:", error);
    res.status(500).json({ message: "Failed to update marks", error: error.message });
  }
});

/**
 * DELETE /api/marks/:mark_record_id
 * Delete a specific subject mark record.
 * - Admin: can delete any mark record.
 * - Teacher: can delete ONLY records for classes and subjects assigned to them.
 * Never deletes other subjects' marks accidentally.
 */
router.delete("/:mark_record_id", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { mark_record_id } = req.params;

    const existingRes = await pool.query(
      `SELECT m.*, s.class, sub.subject_name 
       FROM student_subject_marks m
       JOIN student s ON m.reg_no = s.reg_no
       JOIN subjects sub ON m.subject_id = sub.subject_id
       WHERE m.mark_record_id = $1`,
      [mark_record_id]
    );

    if (existingRes.rows.length === 0) {
      return res.status(404).json({ message: "Marks record not found." });
    }
    const current = existingRes.rows[0];

    // Teacher authorization: must teach this subject in this student's class
    if (req.user.role === "teacher") {
      const isAssigned = await verifyTeacherAssignment(req.user.id, current.class, current.subject_id);
      if (!isAssigned) {
        return res.status(403).json({
          message: `Access forbidden: You are not authorized to delete marks for ${current.subject_name} in Class ${current.class}.`,
        });
      }
    }

    const deleteRes = await pool.query(
      `DELETE FROM student_subject_marks WHERE mark_record_id = $1 RETURNING *`,
      [mark_record_id]
    );

    res.json({
      message: `Mark record for ${current.subject_name} deleted successfully.`,
      deletedRecord: deleteRes.rows[0],
    });
  } catch (error) {
    console.error("Error deleting marks:", error);
    res.status(500).json({ message: "Failed to delete marks", error: error.message });
  }
});

module.exports = router;
