const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

router.use(verifyToken);

/**
 * Helper to resolve subject from ID or code/name
 */
async function resolveSubject(subjectIdent) {
  if (!subjectIdent) return null;
  if (typeof subjectIdent === "number" || /^\d+$/.test(String(subjectIdent).trim())) {
    const res = await pool.query(
      "SELECT subject_id, subject_code, subject_name FROM subjects WHERE subject_id = $1",
      [parseInt(subjectIdent, 10)]
    );
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
 * Helper to resolve class record from student class string
 */
async function resolveClass(classStr) {
  if (!classStr) return null;
  const clean = String(classStr).trim().toUpperCase();
  const res = await pool.query(
    `SELECT class_id, class_code, class_name, section 
     FROM classes 
     WHERE UPPER(TRIM(class_code)) = $1 
        OR UPPER(TRIM(class_name || ' ' || section)) = $1`,
    [clean]
  );
  return res.rows[0] || null;
}

/**
 * Helper to verify teacher assignment for class and subject
 */
async function verifyTeacherClassSubject(teacherId, classId, subjectId) {
  const res = await pool.query(
    `SELECT assignment_id 
     FROM teacher_assignment 
     WHERE teacher_id = $1 AND class_id = $2 AND subject_id = $3`,
    [teacherId, classId, subjectId]
  );
  return res.rows[0] || null;
}

/**
 * GET all attendance records
 * - Admin: view all records (optional filters by class, date, subject_id, reg_no)
 * - Teacher: view attendance only for students in assigned classes & subjects
 */
router.get("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { reg_no, class: filterClass, attendance_date, subject_id } = req.query;

    let query = `
      SELECT
          a.attend_id,
          a.reg_no,
          s.full_name,
          s.class,
          TO_CHAR(a.attendance_date, 'YYYY-MM-DD') AS attendance_date,
          a.status,
          COALESCE(a.attendance_type, CASE WHEN a.subject_id IS NOT NULL THEN 'Subject' ELSE 'General' END) AS attendance_type,
          a.subject_id,
          sub.subject_code,
          sub.subject_name,
          a.timetable_id,
          a.assignment_id,
          a.recorded_by
      FROM attendance a
      JOIN student s ON a.reg_no = s.reg_no
      LEFT JOIN subjects sub ON a.subject_id = sub.subject_id
      WHERE 1=1
    `;
    const params = [];
    let paramIndex = 1;

    if (req.user.role === "teacher") {
      query += `
        AND (
          (COALESCE(a.attendance_type, CASE WHEN a.subject_id IS NOT NULL THEN 'Subject' ELSE 'General' END) = 'Subject'
           AND EXISTS (
             SELECT 1 FROM teacher_assignment ta
             JOIN classes c ON ta.class_id = c.class_id
             WHERE ta.teacher_id = $${paramIndex}
               AND ta.subject_id = a.subject_id
               AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM(s.class))
                    OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM(s.class)))
           ))
          OR
          (COALESCE(a.attendance_type, CASE WHEN a.subject_id IS NOT NULL THEN 'Subject' ELSE 'General' END) = 'General'
           AND EXISTS (
             SELECT 1 FROM teacher_assignment ta
             JOIN classes c ON ta.class_id = c.class_id
             WHERE ta.teacher_id = $${paramIndex}
               AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM(s.class))
                    OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM(s.class)))
           ))
        )
      `;
      params.push(req.user.id);
      paramIndex++;
    }

    if (reg_no && reg_no.trim()) {
      query += ` AND a.reg_no ILIKE $${paramIndex}`;
      params.push(`%${reg_no.trim()}%`);
      paramIndex++;
    }

    if (filterClass && filterClass.trim()) {
      query += ` AND UPPER(TRIM(s.class)) = UPPER(TRIM($${paramIndex}))`;
      params.push(filterClass.trim());
      paramIndex++;
    }

    if (attendance_date && attendance_date.trim()) {
      query += ` AND a.attendance_date = $${paramIndex}`;
      params.push(attendance_date.trim());
      paramIndex++;
    }

    if (subject_id) {
      const sub = await resolveSubject(subject_id);
      if (sub) {
        query += ` AND a.subject_id = $${paramIndex}`;
        params.push(sub.subject_id);
        paramIndex++;
      }
    }

    query += ` ORDER BY a.attendance_date DESC, s.class ASC, a.reg_no ASC`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching attendance:", error);
    res.status(500).json({
      message: "Failed to fetch attendance",
      error: error.message,
    });
  }
});

/**
 * GET attendance for a specific student
 */
router.get("/:reg_no", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { reg_no } = req.params;

    // Check student existence
    const studentRes = await pool.query(
      "SELECT reg_no, full_name, class FROM student WHERE reg_no = $1",
      [reg_no]
    );
    if (studentRes.rows.length === 0) {
      return res.status(404).json({ message: "Student not found" });
    }

    const studentClass = studentRes.rows[0].class;

    if (req.user.role === "teacher") {
      const authCheck = await pool.query(
        `SELECT 1 FROM teacher_assignment ta
         JOIN classes c ON ta.class_id = c.class_id
         WHERE ta.teacher_id = $1 
           AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM($2))
                OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM($2)))`,
        [req.user.id, studentClass]
      );
      if (authCheck.rows.length === 0) {
        return res.status(403).json({ message: "Access forbidden: Student is not in your assigned class." });
      }
    }

    let query = `
      SELECT
          a.attend_id,
          a.reg_no,
          s.full_name,
          s.class,
          TO_CHAR(a.attendance_date, 'YYYY-MM-DD') AS attendance_date,
          a.status,
          COALESCE(a.attendance_type, CASE WHEN a.subject_id IS NOT NULL THEN 'Subject' ELSE 'General' END) AS attendance_type,
          a.subject_id,
          sub.subject_code,
          sub.subject_name,
          a.timetable_id,
          a.assignment_id,
          a.recorded_by
      FROM attendance a
      JOIN student s ON a.reg_no = s.reg_no
      LEFT JOIN subjects sub ON a.subject_id = sub.subject_id
      WHERE a.reg_no = $1
    `;
    const params = [reg_no];

    if (req.user.role === "teacher") {
      query += `
        AND (
          (COALESCE(a.attendance_type, 'Subject') = 'Subject'
           AND EXISTS (
             SELECT 1 FROM teacher_assignment ta
             JOIN classes c ON ta.class_id = c.class_id
             WHERE ta.teacher_id = $2
               AND ta.subject_id = a.subject_id
               AND (UPPER(TRIM(c.class_code)) = UPPER(TRIM(s.class))
                    OR UPPER(TRIM(c.class_name || ' ' || c.section)) = UPPER(TRIM(s.class)))
           ))
          OR
          (COALESCE(a.attendance_type, 'General') = 'General')
        )
      `;
      params.push(req.user.id);
    }

    query += ` ORDER BY a.attendance_date DESC, a.attend_id DESC`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching student attendance:", error);
    res.status(500).json({
      message: "Failed to fetch student attendance",
      error: error.message,
    });
  }
});

/**
 * POST attendance
 * - Teacher: strictly records attendance for assigned classes and subjects
 * - Mutual consistency: student.class -> classes.class_id -> teacher_assignment -> timetable period
 */
router.post("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { reg_no, attendance_date, status, subject_id, timetable_id, attendance_type } = req.body;

    if (!reg_no || !attendance_date || !status) {
      return res.status(400).json({
        message: "Student reg_no, attendance_date, and status are required.",
      });
    }

    if (!["Present", "Absent"].includes(status)) {
      return res.status(400).json({ message: "Status must be 'Present' or 'Absent'." });
    }

    // Verify student exists and fetch class
    const studentRes = await pool.query(
      "SELECT reg_no, full_name, class FROM student WHERE reg_no = $1",
      [reg_no]
    );
    if (studentRes.rows.length === 0) {
      return res.status(404).json({ message: "Student not found." });
    }
    const student = studentRes.rows[0];

    // Resolve class_id
    const classRecord = await resolveClass(student.class);
    if (!classRecord) {
      return res.status(400).json({
        message: `Student's class '${student.class}' is not registered in the classes table.`,
      });
    }

    let resolvedSubject = null;
    let assignmentId = null;
    let finalAttendanceType = attendance_type || "Subject";
    const recordedBy = req.user.role === "teacher" ? req.user.id : null;

    if (req.user.role === "teacher") {
      // Teachers MUST provide a subject and be assigned to it
      if (!subject_id) {
        return res.status(400).json({
          message: "subject_id is required for teacher attendance recording.",
        });
      }

      resolvedSubject = await resolveSubject(subject_id);
      if (!resolvedSubject) {
        return res.status(400).json({
          message: `Subject '${subject_id}' not found. Note that 'Others' has been retired.`,
        });
      }

      // Mutual consistency: verify teacher is actively assigned to class & subject
      const assignment = await verifyTeacherClassSubject(
        req.user.id,
        classRecord.class_id,
        resolvedSubject.subject_id
      );
      if (!assignment) {
        return res.status(403).json({
          message: `Access forbidden: You are not assigned to teach ${resolvedSubject.subject_name} in Class ${student.class}.`,
        });
      }
      assignmentId = assignment.assignment_id;
      finalAttendanceType = "Subject";

      // If timetable_id is provided, verify period mutual consistency
      if (timetable_id) {
        const ttCheck = await pool.query(
          `SELECT timetable_id FROM timetable
           WHERE timetable_id = $1 
             AND teacher_id = $2 
             AND class_id = $3 
             AND subject_id = $4`,
          [timetable_id, req.user.id, classRecord.class_id, resolvedSubject.subject_id]
        );
        if (ttCheck.rows.length === 0) {
          return res.status(400).json({
            message: "Inconsistent timetable period. The selected period does not belong to your assigned class and subject.",
          });
        }
      }
    } else {
      // Admin workflow: can record Subject or General attendance
      if (subject_id) {
        resolvedSubject = await resolveSubject(subject_id);
        if (!resolvedSubject) {
          return res.status(400).json({ message: `Subject '${subject_id}' not found.` });
        }
        finalAttendanceType = "Subject";

        // Check if an existing assignment matches
        const assignCheck = await pool.query(
          `SELECT assignment_id FROM teacher_assignment WHERE class_id = $1 AND subject_id = $2 LIMIT 1`,
          [classRecord.class_id, resolvedSubject.subject_id]
        );
        if (assignCheck.rows.length > 0) {
          assignmentId = assignCheck.rows[0].assignment_id;
        }

        if (timetable_id) {
          const ttCheck = await pool.query(
            `SELECT timetable_id FROM timetable WHERE timetable_id = $1 AND class_id = $2 AND subject_id = $3`,
            [timetable_id, classRecord.class_id, resolvedSubject.subject_id]
          );
          if (ttCheck.rows.length === 0) {
            return res.status(400).json({
              message: "Inconsistent timetable period for the specified class and subject.",
            });
          }
        }
      } else {
        finalAttendanceType = "General";
      }
    }

    // Check duplicate attendance record according to partial index rules
    let duplicateQuery = "";
    let duplicateParams = [];

    if (finalAttendanceType === "Subject") {
      if (timetable_id) {
        duplicateQuery = `
          SELECT attend_id FROM attendance 
          WHERE reg_no = $1 
            AND attendance_date = $2 
            AND subject_id = $3 
            AND timetable_id = $4 
            AND attendance_type = 'Subject'
        `;
        duplicateParams = [reg_no, attendance_date, resolvedSubject.subject_id, timetable_id];
      } else {
        duplicateQuery = `
          SELECT attend_id FROM attendance 
          WHERE reg_no = $1 
            AND attendance_date = $2 
            AND subject_id = $3 
            AND timetable_id IS NULL 
            AND attendance_type = 'Subject'
        `;
        duplicateParams = [reg_no, attendance_date, resolvedSubject.subject_id];
      }
    } else {
      duplicateQuery = `
        SELECT attend_id FROM attendance 
        WHERE reg_no = $1 
          AND attendance_date = $2 
          AND attendance_type = 'General'
      `;
      duplicateParams = [reg_no, attendance_date];
    }

    const duplicateCheck = await pool.query(duplicateQuery, duplicateParams);
    if (duplicateCheck.rows.length > 0) {
      return res.status(409).json({
        message: `Attendance for student ${reg_no} on ${attendance_date} (${finalAttendanceType}${
          resolvedSubject ? " - " + resolvedSubject.subject_name : ""
        }) has already been recorded. Use edit if you need to update it.`,
      });
    }

    const result = await pool.query(
      `
      INSERT INTO attendance (
          reg_no,
          attendance_date,
          status,
          subject_id,
          timetable_id,
          assignment_id,
          attendance_type,
          recorded_by
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING *;
      `,
      [
        reg_no,
        attendance_date,
        status,
        resolvedSubject ? resolvedSubject.subject_id : null,
        timetable_id || null,
        assignmentId || null,
        finalAttendanceType,
        recordedBy,
      ]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("Error adding attendance:", error);
    if (error.code === "23505") {
      return res.status(409).json({
        message: `Duplicate attendance record detected: Attendance for student ${req.body.reg_no} on ${req.body.attendance_date} already exists.`,
      });
    }
    res.status(500).json({
      message: "Failed to add attendance",
      error: error.message,
    });
  }
});

/**
 * UPDATE attendance
 * - Teachers can only update attendance for their assigned classes and subjects
 * - Cannot modify General attendance
 */
router.put("/:attend_id", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { attend_id } = req.params;
    const { attendance_date, status, subject_id, timetable_id } = req.body;

    if (status && !["Present", "Absent"].includes(status)) {
      return res.status(400).json({ message: "Status must be 'Present' or 'Absent'." });
    }

    const existing = await pool.query(
      `SELECT a.*, s.class 
       FROM attendance a 
       JOIN student s ON a.reg_no = s.reg_no 
       WHERE a.attend_id = $1`,
      [attend_id]
    );

    if (existing.rows.length === 0) {
      return res.status(404).json({ message: "Attendance record not found" });
    }

    const record = existing.rows[0];

    if (req.user.role === "teacher") {
      const recordType = record.attendance_type || (record.subject_id ? "Subject" : "General");
      if (recordType === "General") {
        return res.status(403).json({
          message: "Access forbidden: General attendance records can only be managed by administrators.",
        });
      }

      const classRecord = await resolveClass(record.class);
      if (!classRecord) {
        return res.status(403).json({ message: "Student class could not be resolved." });
      }

      // Check teacher assignment for current subject
      const currentAssignment = await verifyTeacherClassSubject(
        req.user.id,
        classRecord.class_id,
        record.subject_id
      );
      if (!currentAssignment) {
        return res.status(403).json({
          message: "Access forbidden: You are not assigned to manage attendance for this class and subject.",
        });
      }

      // If updating subject_id, verify new subject assignment
      if (subject_id && subject_id !== record.subject_id) {
        const newSub = await resolveSubject(subject_id);
        if (!newSub) {
          return res.status(400).json({ message: "Target subject not found." });
        }
        const newAssignment = await verifyTeacherClassSubject(
          req.user.id,
          classRecord.class_id,
          newSub.subject_id
        );
        if (!newAssignment) {
          return res.status(403).json({
            message: `Access forbidden: You are not assigned to teach ${newSub.subject_name} in Class ${record.class}.`,
          });
        }
      }
    }

    // Resolve subject if updating
    let targetSubjectId = record.subject_id;
    if (subject_id !== undefined) {
      if (subject_id) {
        const sub = await resolveSubject(subject_id);
        if (!sub) return res.status(400).json({ message: "Target subject not found." });
        targetSubjectId = sub.subject_id;
      } else {
        targetSubjectId = null;
      }
    }

    const result = await pool.query(
      `
      UPDATE attendance
      SET
          attendance_date = COALESCE($1, attendance_date),
          status = COALESCE($2, status),
          subject_id = $3,
          timetable_id = COALESCE($4, timetable_id)
      WHERE attend_id = $5
      RETURNING *;
      `,
      [
        attendance_date,
        status,
        targetSubjectId,
        timetable_id !== undefined ? timetable_id : record.timetable_id,
        attend_id,
      ]
    );

    res.json(result.rows[0]);
  } catch (error) {
    console.error("Error updating attendance:", error);
    if (error.code === "23505") {
      return res.status(409).json({
        message: "Updating this attendance record would violate uniqueness constraints.",
      });
    }
    res.status(500).json({
      message: "Failed to update attendance",
      error: error.message,
    });
  }
});

/**
 * DELETE attendance
 * - Administrator: can delete any attendance record
 * - Teacher: can delete ONLY subject-specific attendance records for their assigned classes and subjects
 * - Teachers CANNOT delete General attendance records
 */
router.delete("/:attend_id", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { attend_id } = req.params;

    const existing = await pool.query(
      `SELECT a.*, s.class 
       FROM attendance a 
       JOIN student s ON a.reg_no = s.reg_no 
       WHERE a.attend_id = $1`,
      [attend_id]
    );

    if (existing.rows.length === 0) {
      return res.status(404).json({
        message: "Attendance record not found",
      });
    }

    const record = existing.rows[0];

    if (req.user.role === "teacher") {
      const recordType = record.attendance_type || (record.subject_id ? "Subject" : "General");
      if (recordType === "General") {
        return res.status(403).json({
          message: "Access forbidden: General attendance records can only be managed by administrators.",
        });
      }

      const classRecord = await resolveClass(record.class);
      if (!classRecord) {
        return res.status(403).json({ message: "Student class could not be resolved." });
      }

      const isAssigned = await verifyTeacherClassSubject(
        req.user.id,
        classRecord.class_id,
        record.subject_id
      );
      if (!isAssigned) {
        return res.status(403).json({
          message: "Access forbidden: You are not assigned to manage attendance for this class and subject.",
        });
      }
    }

    const result = await pool.query(
      `
      DELETE FROM attendance
      WHERE attend_id = $1
      RETURNING *;
      `,
      [attend_id]
    );

    res.json({
      message: "Attendance deleted successfully",
      attendance: result.rows[0],
    });
  } catch (error) {
    console.error("Error deleting attendance:", error);
    res.status(500).json({
      message: "Failed to delete attendance",
      error: error.message,
    });
  }
});

module.exports = router;
