const express = require("express");
const router = express.Router();
const pool = require("../db");
const { verifyToken, requireAdmin, requireTeacherOrAdmin } = require("../middleware/auth");

router.use(verifyToken);

/**
 * GET /api/announcements
 * Retrieve announcements based on role
 */
router.get("/", requireTeacherOrAdmin, async (req, res) => {
  try {
    let query;
    let params = [];

    if (req.user.role === "admin") {
      // Admin sees all announcements, newest first
      query = `
        SELECT announcement_id, title, content, target_audience, is_active, created_by, created_at, updated_at
        FROM announcements
        ORDER BY created_at DESC
      `;
    } else {
      // Teachers see active announcements targeted to 'All' or 'Teachers'
      query = `
        SELECT announcement_id, title, content, target_audience, is_active, created_by, created_at, updated_at
        FROM announcements
        WHERE is_active = TRUE AND (target_audience = 'All' OR target_audience = 'Teachers')
        ORDER BY created_at DESC
      `;
    }

    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (error) {
    console.error("Error fetching announcements:", error);
    res.status(500).json({ message: "Failed to fetch announcements." });
  }
});

/**
 * POST /api/announcements
 * Create new announcement (Admin only)
 */
router.post("/", requireAdmin, async (req, res) => {
  try {
    const { title, content, target_audience = "All", is_active = true } = req.body;

    if (!title || !content) {
      return res.status(400).json({ message: "Title and content are required." });
    }

    const result = await pool.query(
      `INSERT INTO announcements (title, content, target_audience, is_active, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [title.trim(), content.trim(), target_audience, is_active, req.user.username || "admin"]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("Error creating announcement:", error);
    res.status(500).json({ message: "Failed to create announcement.", error: error.message });
  }
});

/**
 * PUT /api/announcements/:announcement_id
 * Update announcement (Admin only)
 */
router.put("/:announcement_id", requireAdmin, async (req, res) => {
  try {
    const { announcement_id } = req.params;
    const { title, content, target_audience, is_active } = req.body;

    const result = await pool.query(
      `UPDATE announcements
       SET title = $1, content = $2, target_audience = $3, is_active = $4, updated_at = CURRENT_TIMESTAMP
       WHERE announcement_id = $5
       RETURNING *`,
      [title.trim(), content.trim(), target_audience, is_active, announcement_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Announcement not found." });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error("Error updating announcement:", error);
    res.status(500).json({ message: "Failed to update announcement.", error: error.message });
  }
});

/**
 * DELETE /api/announcements/:announcement_id
 * Delete announcement (Admin only)
 */
router.delete("/:announcement_id", requireAdmin, async (req, res) => {
  try {
    const { announcement_id } = req.params;

    const result = await pool.query("DELETE FROM announcements WHERE announcement_id = $1 RETURNING *", [
      announcement_id,
    ]);

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Announcement not found." });
    }

    res.json({ message: "Announcement deleted successfully." });
  } catch (error) {
    console.error("Error deleting announcement:", error);
    res.status(500).json({ message: "Failed to delete announcement." });
  }
});

module.exports = router;
