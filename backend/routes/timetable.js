const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

router.use(verifyToken);

/**
 * GET /api/timetable
 * Fetch timetable entries (optional filter by class_id or teacher_id)
 */
router.get("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    const { class_id, teacher_id, day_of_week } = req.query;
    let query = `
      SELECT 
        tt.timetable_id,
        tt.class_id,
        c.class_name,
        c.section,
        c.class_code,
        tt.subject_id,
        s.subject_code,
        s.subject_name,
        tt.teacher_id,
        t.full_name AS teacher_name,
        tt.day_of_week,
        TO_CHAR(tt.start_time, 'HH24:MI') AS start_time,
        TO_CHAR(tt.end_time, 'HH24:MI') AS end_time,
        tt.room_number
      FROM timetable tt
      JOIN classes c ON tt.class_id = c.class_id
      JOIN subjects s ON tt.subject_id = s.subject_id
      JOIN teacher t ON tt.teacher_id = t.teacher_id
      WHERE 1=1
    `;
    const params = [];

    if (class_id) {
      params.push(class_id);
      query += ` AND tt.class_id = $${params.length}`;
    }

    if (teacher_id) {
      params.push(teacher_id);
      query += ` AND tt.teacher_id = $${params.length}`;
    }

    if (day_of_week) {
      params.push(day_of_week);
      query += ` AND tt.day_of_week = $${params.length}`;
    }

    query += ` ORDER BY 
      CASE tt.day_of_week 
        WHEN 'Monday' THEN 1
        WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday' THEN 4
        WHEN 'Friday' THEN 5
        WHEN 'Saturday' THEN 6
        ELSE 7
      END,
      tt.start_time ASC`;

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching timetable:", error);
    res.status(500).json({ message: "Failed to fetch timetable." });
  }
});

/**
 * GET /api/timetable/my-schedule
 * Get timetable for currently logged in teacher
 */
router.get("/my-schedule", async (req, res) => {
  try {
    if (req.user.role !== "teacher") {
      return res.status(403).json({ message: "Teacher access required." });
    }

    const result = await pool.query(
      `SELECT 
        tt.timetable_id,
        tt.class_id,
        c.class_name,
        c.section,
        c.class_code,
        tt.subject_id,
        s.subject_code,
        s.subject_name,
        tt.day_of_week,
        TO_CHAR(tt.start_time, 'HH24:MI') AS start_time,
        TO_CHAR(tt.end_time, 'HH24:MI') AS end_time,
        tt.room_number
      FROM timetable tt
      JOIN classes c ON tt.class_id = c.class_id
      JOIN subjects s ON tt.subject_id = s.subject_id
      WHERE tt.teacher_id = $1
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
        tt.start_time ASC`,
      [req.user.id]
    );

    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching teacher schedule:", error);
    res.status(500).json({ message: "Failed to fetch schedule." });
  }
});

/**
 * Helper: Convert time string (e.g., "09:30" or "9:30") to minutes from midnight
 */
function timeToMinutes(tStr) {
  if (!tStr) return 0;
  const parts = tStr.split(":").map(Number);
  return parts[0] * 60 + (parts[1] || 0);
}

/**
 * Helper: Check schedule conflicts
 * NOTE: Schedule overlap prevention is enforced at the application layer.
 * Direct SQL INSERTs executed outside this API are not checked by PostgreSQL.
 */
async function checkConflicts(class_id, teacher_id, day_of_week, start_time, end_time, exclude_id = null) {
  // Check 1: Class overlap conflict
  let classConflictQuery = `
    SELECT tt.timetable_id, c.class_code, s.subject_name, tt.start_time, tt.end_time
    FROM timetable tt
    JOIN classes c ON tt.class_id = c.class_id
    JOIN subjects s ON tt.subject_id = s.subject_id
    WHERE tt.class_id = $1 AND tt.day_of_week = $2
      AND (tt.start_time < $4::time AND tt.end_time > $3::time)
  `;
  const classParams = [class_id, day_of_week, start_time, end_time];
  if (exclude_id) {
    classConflictQuery += ` AND tt.timetable_id <> $5`;
    classParams.push(exclude_id);
  }
  const classConflict = await pool.query(classConflictQuery, classParams);
  if (classConflict.rows.length > 0) {
    const existing = classConflict.rows[0];
    return `Class schedule conflict: Class ${existing.class_code} already has ${existing.subject_name} scheduled between ${existing.start_time} and ${existing.end_time} on ${day_of_week}.`;
  }

  // Check 2: Teacher overlap conflict
  let teacherConflictQuery = `
    SELECT tt.timetable_id, t.full_name, c.class_code, s.subject_name, tt.start_time, tt.end_time
    FROM timetable tt
    JOIN teacher t ON tt.teacher_id = t.teacher_id
    JOIN classes c ON tt.class_id = c.class_id
    JOIN subjects s ON tt.subject_id = s.subject_id
    WHERE tt.teacher_id = $1 AND tt.day_of_week = $2
      AND (tt.start_time < $4::time AND tt.end_time > $3::time)
  `;
  const teacherParams = [teacher_id, day_of_week, start_time, end_time];
  if (exclude_id) {
    teacherConflictQuery += ` AND tt.timetable_id <> $5`;
    teacherParams.push(exclude_id);
  }
  const teacherConflict = await pool.query(teacherConflictQuery, teacherParams);
  if (teacherConflict.rows.length > 0) {
    const existing = teacherConflict.rows[0];
    return `Teacher schedule conflict: ${existing.full_name} is already assigned to Class ${existing.class_code} for ${existing.subject_name} between ${existing.start_time} and ${existing.end_time} on ${day_of_week}.`;
  }

  return null;
}

/**
 * POST /api/timetable
 * Create timetable entry with conflict prevention (Admin only)
 */
router.post("/", requireAdmin, async (req, res) => {
  try {
    const { class_id, subject_id, teacher_id, day_of_week, start_time, end_time, room_number } = req.body;

    if (!class_id || !subject_id || !teacher_id || !day_of_week || !start_time || !end_time) {
      return res.status(400).json({ message: "All timetable fields are required." });
    }

    if (timeToMinutes(start_time) >= timeToMinutes(end_time)) {
      return res.status(400).json({ message: "Start time must be before end time." });
    }

    // Check for scheduling conflicts
    const conflictMessage = await checkConflicts(class_id, teacher_id, day_of_week, start_time, end_time);
    if (conflictMessage) {
      return res.status(409).json({ message: conflictMessage });
    }

    const result = await pool.query(
      `INSERT INTO timetable (class_id, subject_id, teacher_id, day_of_week, start_time, end_time, room_number)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [class_id, subject_id, teacher_id, day_of_week, start_time, end_time, room_number || null]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("Error creating timetable entry:", error);
    res.status(500).json({ message: "Failed to create timetable entry.", error: error.message });
  }
});

/**
 * PUT /api/timetable/:timetable_id
 * Update timetable entry with conflict checking (Admin only)
 */
router.put("/:timetable_id", requireAdmin, async (req, res) => {
  try {
    const { timetable_id } = req.params;
    const { class_id, subject_id, teacher_id, day_of_week, start_time, end_time, room_number } = req.body;

    if (timeToMinutes(start_time) >= timeToMinutes(end_time)) {
      return res.status(400).json({ message: "Start time must be before end time." });
    }

    const conflictMessage = await checkConflicts(
      class_id,
      teacher_id,
      day_of_week,
      start_time,
      end_time,
      timetable_id
    );
    if (conflictMessage) {
      return res.status(409).json({ message: conflictMessage });
    }

    const result = await pool.query(
      `UPDATE timetable
       SET class_id = $1, subject_id = $2, teacher_id = $3, day_of_week = $4, start_time = $5, end_time = $6, room_number = $7
       WHERE timetable_id = $8
       RETURNING *`,
      [class_id, subject_id, teacher_id, day_of_week, start_time, end_time, room_number, timetable_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Timetable entry not found." });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error("Error updating timetable entry:", error);
    res.status(500).json({ message: "Failed to update timetable entry.", error: error.message });
  }
});

/**
 * DELETE /api/timetable/:timetable_id
 * Remove timetable entry (Admin only)
 */
router.delete("/:timetable_id", requireAdmin, async (req, res) => {
  try {
    const { timetable_id } = req.params;

    const result = await pool.query("DELETE FROM timetable WHERE timetable_id = $1 RETURNING *", [timetable_id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Timetable entry not found." });
    }

    res.json({ message: "Timetable entry deleted successfully." });
  } catch (error) {
    console.error("Error deleting timetable entry:", error);
    res.status(500).json({ message: "Failed to delete timetable entry." });
  }
});

module.exports = router;
