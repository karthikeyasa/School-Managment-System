const express = require("express");
const router = express.Router();
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const pool = require("../db");
const { JWT_SECRET, verifyToken } = require("../middleware/auth");

/**
 * POST /api/auth/login
 * Unified secure login supporting Administrator and Teacher roles.
 * Role claim is derived strictly from trusted database records.
 */
router.post("/login", async (req, res) => {
  try {
    const { username, password, role: requestedRole } = req.body;

    if (!username || !password || typeof username !== "string" || typeof password !== "string") {
      return res.status(400).json({ message: "Username and password are required." });
    }

    const cleanUsername = username.trim();

    // 1. If requested role is 'admin', check administrator table
    if (!requestedRole || requestedRole === "admin") {
      const adminResult = await pool.query(
        `SELECT admin_id, username, password, COALESCE(role, 'admin') AS role
         FROM administrator
         WHERE username = $1`,
        [cleanUsername]
      );

      if (adminResult.rows.length > 0) {
        const admin = adminResult.rows[0];
        let passwordValid = false;

        // Verify with bcrypt
        if (admin.password.startsWith("$2a$") || admin.password.startsWith("$2b$")) {
          passwordValid = await bcrypt.compare(password, admin.password);
        } else {
          // Backward compatibility: legacy plaintext match
          passwordValid = admin.password === password;
          if (passwordValid) {
            // Automatically upgrade password to secure bcrypt hash in the database
            const upgradedHash = await bcrypt.hash(password, 10);
            await pool.query("UPDATE administrator SET password = $1 WHERE admin_id = $2", [
              upgradedHash,
              admin.admin_id,
            ]);
          }
        }

        if (passwordValid) {
          // Trusted role strictly set from the database record
          const trustedRole = admin.role || "admin";
          const payload = {
            id: admin.admin_id,
            username: admin.username,
            role: trustedRole,
            name: admin.username,
          };

          const token = jwt.sign(payload, JWT_SECRET, { expiresIn: "8h" });

          return res.json({
            message: "Login successful",
            token,
            user: payload,
          });
        } else if (requestedRole === "admin") {
          return res.status(401).json({ message: "Invalid username or password." });
        }
      } else if (requestedRole === "admin") {
        return res.status(401).json({ message: "Invalid username or password." });
      }
    }

    // 2. If requested role is 'teacher' (or fallback when role is not specified)
    if (!requestedRole || requestedRole === "teacher") {
      const teacherResult = await pool.query(
        `SELECT teacher_id, full_name, email, phone, status, password_hash
         FROM teacher
         WHERE teacher_id = $1 OR email = $1`,
        [cleanUsername]
      );

      if (teacherResult.rows.length > 0) {
        const teacher = teacherResult.rows[0];

        if (teacher.status !== "Active") {
          return res.status(403).json({
            message: `Account is ${teacher.status}. Please contact the administrator.`,
          });
        }

        let passwordValid = false;
        if (teacher.password_hash.startsWith("$2a$") || teacher.password_hash.startsWith("$2b$")) {
          passwordValid = await bcrypt.compare(password, teacher.password_hash);
        } else {
          passwordValid = teacher.password_hash === password;
        }

        if (passwordValid) {
          // Trusted role strictly 'teacher'
          const payload = {
            id: teacher.teacher_id,
            username: teacher.email,
            role: "teacher",
            name: teacher.full_name,
            email: teacher.email,
          };

          const token = jwt.sign(payload, JWT_SECRET, { expiresIn: "8h" });

          return res.json({
            message: "Login successful",
            token,
            user: payload,
          });
        } else {
          return res.status(401).json({ message: "Invalid credentials." });
        }
      } else {
        return res.status(401).json({ message: "Invalid credentials." });
      }
    }

    return res.status(401).json({ message: "Invalid username or password." });
  } catch (error) {
    console.error("Login error:", error);
    return res.status(500).json({ message: "Internal server error during authentication." });
  }
});

/**
 * GET /api/auth/me
 * Validate current session and retrieve verified user details
 */
router.get("/me", verifyToken, async (req, res) => {
  res.json({
    user: req.user,
  });
});

module.exports = router;
