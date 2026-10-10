const jwt = require("jsonwebtoken");

// Fail securely at application startup if JWT_SECRET is missing or empty
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET || JWT_SECRET.trim() === "") {
  throw new Error(
    "FATAL ERROR: JWT_SECRET environment variable is missing or empty. The server cannot start securely without a configured JWT secret."
  );
}

/**
 * Verify JWT token from the Authorization header: 'Bearer <token>'
 */
function verifyToken(req, res, next) {
  const authHeader = req.headers["authorization"] || req.headers["Authorization"];
  if (!authHeader) {
    return res.status(401).json({ message: "Authentication token required. Please log in." });
  }

  const parts = authHeader.split(" ");
  if (parts.length !== 2 || parts[0].toLowerCase() !== "bearer") {
    return res.status(401).json({ message: "Invalid authorization header format. Expected 'Bearer <token>'." });
  }

  const token = parts[1].trim();
  if (!token) {
    return res.status(401).json({ message: "Authentication token is missing." });
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    // Payload contains trusted database claims: { id, username, role, name, email }
    req.user = decoded;
    next();
  } catch (err) {
    if (err.name === "TokenExpiredError") {
      return res.status(401).json({ message: "Session expired. Please log in again." });
    }
    return res.status(401).json({ message: "Invalid authentication token." });
  }
}

/**
 * Require Administrator role on protected endpoints
 */
function requireAdmin(req, res, next) {
  if (!req.user || req.user.role !== "admin") {
    return res.status(403).json({ message: "Access forbidden: Administrator privileges required." });
  }
  next();
}

/**
 * Require Teacher role on protected endpoints
 */
function requireTeacher(req, res, next) {
  if (!req.user || req.user.role !== "teacher") {
    return res.status(403).json({ message: "Access forbidden: Teacher privileges required." });
  }
  next();
}

/**
 * Allow either Administrator or Teacher role
 */
function requireTeacherOrAdmin(req, res, next) {
  if (!req.user || (req.user.role !== "admin" && req.user.role !== "teacher")) {
    return res.status(403).json({ message: "Access forbidden: Authorized user required." });
  }
  next();
}

module.exports = {
  JWT_SECRET,
  verifyToken,
  requireAdmin,
  requireTeacher,
  requireTeacherOrAdmin,
};
