require("dotenv").config({
  path: __dirname + "/.env",
});

// Fail securely at application startup if JWT_SECRET is missing
if (!process.env.JWT_SECRET || process.env.JWT_SECRET.trim() === "") {
  console.error("FATAL ERROR: JWT_SECRET environment variable is missing or empty.");
  process.exit(1);
}

const express = require("express");
const cors = require("cors");
const pool = require("./db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("./middleware/auth");

const authRoutes = require("./routes/auth");
const teacherRoutes = require("./routes/teachers");
const classRoutes = require("./routes/classes");
const subjectRoutes = require("./routes/subjects");
const assignmentRoutes = require("./routes/assignments");
const timetableRoutes = require("./routes/timetable");
const announcementRoutes = require("./routes/announcements");
const teacherDashboardRoutes = require("./routes/teacherDashboard");
const studentRoutes = require("./routes/students");
const attendanceRoutes = require("./routes/attendance");
const marksRoutes = require("./routes/marks");
const reportsRoutes = require("./routes/reports");

const app = express();

const PORT = process.env.PORT || 5000;

app.use(express.json());
app.use(cors());

// Health check / welcome route
app.get("/", (req, res) => {
  res.json({
    message: "School Management System API is running",
    status: "healthy",
  });
});

// Public authentication routes
app.use("/api/auth", authRoutes);

// Protected module routes
app.use("/api/teachers", teacherRoutes);
app.use("/api/classes", classRoutes);
app.use("/api/subjects", subjectRoutes);
app.use("/api/assignments", assignmentRoutes);
app.use("/api/timetable", timetableRoutes);
app.use("/api/announcements", announcementRoutes);
app.use("/api/teacher-dashboard", teacherDashboardRoutes);
app.use("/api/students", studentRoutes);
app.use("/api/attendance", attendanceRoutes);
app.use("/api/marks", marksRoutes);
app.use("/api/reports", reportsRoutes);

// Dashboard statistics (Administrator only)
app.get("/api/dashboard", verifyToken, requireAdmin, async (req, res) => {
  try {
    const statsQuery = `
      SELECT
        (SELECT COUNT(*) FROM student) AS total_students,
        (SELECT COUNT(*) FROM teacher WHERE status = 'Active') AS total_teachers,
        (SELECT COUNT(*) FROM classes) AS total_classes,
        (SELECT COUNT(*) FROM subjects) AS total_subjects,
        (SELECT COUNT(*) FROM student_subject_marks) AS total_marks,
        (SELECT COUNT(*) FROM attendance) AS total_attendance,
        (
          SELECT COALESCE(ROUND(AVG(average), 2), 0)
          FROM student_reports
        ) AS average_marks;
    `;

    const classQuery = `
      SELECT
        class,
        COUNT(*) AS student_count
      FROM student
      GROUP BY class
      ORDER BY class;
    `;

    const [statsResult, classResult] = await Promise.all([
      pool.query(statsQuery),
      pool.query(classQuery),
    ]);

    res.json({
      statistics: statsResult.rows[0],
      students_by_class: classResult.rows,
    });
  } catch (error) {
    console.error("Dashboard query error:", error);

    res.status(500).json({
      message: "Failed to load dashboard statistics",
    });
  }
});

// Attendance percentage report (Admin and Teachers)
app.get("/api/attendance-report", verifyToken, requireTeacherOrAdmin, async (req, res) => {
  try {
    let query = `
      SELECT
        s.reg_no,
        s.full_name,
        s.class,
        COUNT(a.attend_id) AS total_days,
        COUNT(*) FILTER (
          WHERE a.status = 'Present'
        ) AS present_days,
        COUNT(*) FILTER (
          WHERE a.status = 'Absent'
        ) AS absent_days,
        ROUND(
          (
            COUNT(*) FILTER (
              WHERE a.status = 'Present'
            )::numeric
            / NULLIF(COUNT(a.attend_id), 0)
          ) * 100,
          2
        ) AS attendance_percentage
      FROM student s
      LEFT JOIN attendance a
        ON s.reg_no = a.reg_no
    `;
    const params = [];

    if (req.user.role === "teacher") {
      const authClasses = await pool.query(
        `SELECT DISTINCT c.class_code 
         FROM teacher_assignment ta 
         JOIN classes c ON ta.class_id = c.class_id 
         WHERE ta.teacher_id = $1`,
        [req.user.id]
      );
      const codes = authClasses.rows.map((r) => r.class_code);
      if (codes.length === 0) {
        return res.json([]);
      }
      query += ` WHERE UPPER(TRIM(s.class)) = ANY(SELECT UPPER(TRIM(unnest($1::text[]))))`;
      params.push(codes);
    }

    query += `
      GROUP BY
        s.reg_no,
        s.full_name,
        s.class
      ORDER BY s.reg_no;
    `;

    const result = await pool.query(query, params);

    res.json(result.rows);
  } catch (error) {
    console.error("Attendance report error:", error);

    res.status(500).json({
      message: "Failed to generate attendance report",
    });
  }
});

// Student search and filtering (Admin and Teachers)
app.get("/api/student-search", verifyToken, requireTeacherOrAdmin, async (req, res) => {
  try {
    const { reg_no, name, class_name, gender } = req.query;

    let query = `
      SELECT
        reg_no,
        full_name,
        class,
        date_of_birth,
        gender,
        phone,
        email,
        house_no,
        city,
        pin
      FROM student
      WHERE 1 = 1
    `;

    const values = [];
    let parameterIndex = 1;

    // If teacher, restrict to assigned classes
    if (req.user.role === "teacher") {
      const authClasses = await pool.query(
        `SELECT DISTINCT c.class_code 
         FROM teacher_assignment ta 
         JOIN classes c ON ta.class_id = c.class_id 
         WHERE ta.teacher_id = $1`,
        [req.user.id]
      );
      const codes = authClasses.rows.map((r) => r.class_code);
      if (codes.length === 0) {
        return res.json([]);
      }
      query += ` AND UPPER(TRIM(class)) = ANY(SELECT UPPER(TRIM(unnest($${parameterIndex}::text[]))))`;
      values.push(codes);
      parameterIndex++;
    }

    if (reg_no && reg_no.trim() !== "") {
      query += ` AND reg_no ILIKE $${parameterIndex}`;
      values.push(`%${reg_no.trim()}%`);
      parameterIndex++;
    }

    if (name && name.trim() !== "") {
      query += ` AND full_name ILIKE $${parameterIndex}`;
      values.push(`%${name.trim()}%`);
      parameterIndex++;
    }

    if (class_name && class_name.trim() !== "") {
      query += ` AND UPPER(TRIM(class)) = UPPER(TRIM($${parameterIndex}))`;
      values.push(class_name.trim());
      parameterIndex++;
    }

    if (gender && gender.trim() !== "") {
      query += ` AND gender = $${parameterIndex}`;
      values.push(gender.trim());
      parameterIndex++;
    }

    query += ` ORDER BY reg_no`;

    const result = await pool.query(query, values);

    res.json(result.rows);
  } catch (error) {
    console.error("Student search error:", error);

    res.status(500).json({
      message: "Failed to search students",
    });
  }
});

app.get("/api/test-db", async (req, res) => {
  try {
    const result = await pool.query("SELECT NOW()");

    res.json({
      message: "PostgreSQL connection successful",
      time: result.rows[0].now,
    });
  } catch (error) {
    console.error(error);

    res.status(500).json({
      message: "Database connection failed",
    });
  }
});

// Centralized error handler
app.use((err, req, res, next) => {
  console.error("Unhandled error:", err);
  res.status(500).json({ message: "An unexpected server error occurred." });
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});

module.exports = app;
