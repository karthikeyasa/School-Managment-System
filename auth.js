/**
 * Client-Side Authentication & API Utility
 * School Management System
 */
const SMS_AUTH = {
  TOKEN_KEY: "sms_token",
  USER_KEY: "sms_user",

  getToken() {
    return sessionStorage.getItem(this.TOKEN_KEY);
  },

  getUser() {
    const raw = sessionStorage.getItem(this.USER_KEY);
    try {
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  },

  setAuth(token, user) {
    sessionStorage.setItem(this.TOKEN_KEY, token);
    sessionStorage.setItem(this.USER_KEY, JSON.stringify(user));
    sessionStorage.setItem("isLoggedIn", "true"); // Backward compatibility
  },

  clearAuth() {
    sessionStorage.removeItem(this.TOKEN_KEY);
    sessionStorage.removeItem(this.USER_KEY);
    sessionStorage.removeItem("isLoggedIn");
  },

  isLoggedIn() {
    return !!this.getToken();
  },

  getRole() {
    const user = this.getUser();
    return user ? user.role : null;
  },

  isAdmin() {
    return this.getRole() === "admin";
  },

  isTeacher() {
    return this.getRole() === "teacher";
  },

  /**
   * Enforce page-level authentication and role checking
   */
  requireAuth(requiredRole = null) {
    if (!this.isLoggedIn()) {
      alert("Access Restricted! Please log in first.");
      window.location.href = "index.html";
      return false;
    }

    const currentRole = this.getRole();
    if (requiredRole && currentRole !== requiredRole) {
      if (currentRole === "teacher") {
        alert("Access Forbidden: Administrator privileges required.");
        window.location.href = "teacher_dashboard.html";
      } else {
        alert("Access Forbidden: Unauthorized page.");
        window.location.href = "dbms_home.html";
      }
      return false;
    }
    return true;
  },

  /**
   * Logout helper
   */
  logout() {
    if (confirm("Are you sure you want to log out?")) {
      this.clearAuth();
      window.location.href = "index.html";
    }
  },

  /**
   * Authenticated fetch helper with Bearer token injection
   */
  async fetch(url, options = {}) {
    const headers = options.headers ? { ...options.headers } : {};
    const token = this.getToken();

    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }

    if (options.body && typeof options.body === "string" && !headers["Content-Type"]) {
      headers["Content-Type"] = "application/json";
    }

    try {
      const response = await fetch(url, { ...options, headers });

      if (response.status === 401) {
        alert("Your session has expired or is invalid. Please log in again.");
        this.clearAuth();
        window.location.href = "index.html";
        throw new Error("Unauthorized");
      }

      return response;
    } catch (err) {
      throw err;
    }
  },
};
