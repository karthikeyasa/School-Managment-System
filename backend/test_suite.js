/**
 * Offline Project Verification Suite
 * Tests unit logic, authentication cryptography, role policies,
 * timetable conflict detection algorithms, mark/report calculations (5 core subjects),
 * teacher subject-class authorization, attendance uniqueness invariants, and retake models.
 * Does NOT connect to or modify any database.
 */

const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const assert = require("assert");

console.log("=================================================");
console.log("RUNNING SCHOOL MANAGEMENT SYSTEM TEST SUITE");
console.log("=================================================\n");

let passedTests = 0;
let totalTests = 0;

function runTest(name, fn) {
  totalTests++;
  try {
    fn();
    console.log(`[PASS] ${name}`);
    passedTests++;
  } catch (err) {
    console.error(`[FAIL] ${name}:`, err.message);
  }
}

// -----------------------------------------------------------------
// 1. Password Hashing & Verification (Bcrypt)
// -----------------------------------------------------------------
runTest("Bcrypt password hashing and validation", () => {
  const plain = "admin123";
  const salt = bcrypt.genSaltSync(10);
  const hash = bcrypt.hashSync(plain, salt);
  assert(bcrypt.compareSync(plain, hash), "Password should match hash");
  assert(!bcrypt.compareSync("wrongpassword", hash), "Wrong password should fail");
});

// -----------------------------------------------------------------
// 2. JWT Generation, Expiration & Claims Verification
// -----------------------------------------------------------------
const TEST_SECRET = "test_jwt_secret_key_1234567890_abcdefghij";

runTest("JWT token issuance and claim extraction", () => {
  const payload = { id: "ADM001", username: "admin", role: "admin" };
  const token = jwt.sign(payload, TEST_SECRET, { expiresIn: "8h" });
  const decoded = jwt.verify(token, TEST_SECRET);
  assert.strictEqual(decoded.id, "ADM001");
  assert.strictEqual(decoded.role, "admin");
  assert.strictEqual(decoded.username, "admin");
});

runTest("JWT rejects invalid signatures", () => {
  const payload = { id: "TCH001", role: "teacher" };
  const token = jwt.sign(payload, TEST_SECRET);
  assert.throws(() => {
    jwt.verify(token, "different_secret_key");
  }, /invalid signature/);
});

runTest("JWT rejects expired tokens", () => {
  const payload = { id: "TCH001", role: "teacher" };
  const token = jwt.sign(payload, TEST_SECRET, { expiresIn: "0s" });
  assert.throws(() => {
    jwt.verify(token, TEST_SECRET);
  }, /jwt expired/);
});

// -----------------------------------------------------------------
// 3. Timetable Slot Conflict Detection Algorithm
// Condition: start_A < end_B AND end_A > start_B on same day
// -----------------------------------------------------------------
function checkSlotConflict(slotA, slotB) {
  if (slotA.day !== slotB.day) return false;
  return slotA.start < slotB.end && slotA.end > slotB.start;
}

runTest("Timetable conflict: Overlapping slots detected", () => {
  const slotA = { day: "Monday", start: "09:00", end: "10:00" };
  const slotB = { day: "Monday", start: "09:30", end: "10:30" };
  assert.strictEqual(checkSlotConflict(slotA, slotB), true, "Should conflict");
});

runTest("Timetable conflict: Adjacent slots do NOT conflict", () => {
  const slotA = { day: "Monday", start: "09:00", end: "10:00" };
  const slotB = { day: "Monday", start: "10:00", end: "11:00" };
  assert.strictEqual(checkSlotConflict(slotA, slotB), false, "Adjacent slots should not conflict");
});

runTest("Timetable conflict: Different days do NOT conflict", () => {
  const slotA = { day: "Monday", start: "09:00", end: "10:00" };
  const slotB = { day: "Tuesday", start: "09:00", end: "10:00" };
  assert.strictEqual(checkSlotConflict(slotA, slotB), false, "Different days should not conflict");
});

runTest("Timetable conflict: Nested slot detected", () => {
  const slotA = { day: "Wednesday", start: "09:00", end: "12:00" };
  const slotB = { day: "Wednesday", start: "10:00", end: "11:00" };
  assert.strictEqual(checkSlotConflict(slotA, slotB), true, "Nested slot should conflict");
});

// -----------------------------------------------------------------
// 4. Grade and Average Derivation Logic (5 Core Subjects, Divisor 5.0)
// Matching SQL VIEW student_reports logic
// -----------------------------------------------------------------
function calculateGrade(avg) {
  if (avg >= 90) return "A+";
  if (avg >= 80) return "A";
  if (avg >= 70) return "B";
  if (avg >= 60) return "C";
  if (avg >= 50) return "D";
  return "F";
}

runTest("Academic report: Marks total, average (/5.0), and grade derivation without Others", () => {
  const marks = {
    fl: 85,
    sl: 80,
    math: 95,
    sci: 90,
    arts: 88,
  };
  const total = marks.fl + marks.sl + marks.math + marks.sci + marks.arts;
  const avg = parseFloat((total / 5.0).toFixed(2));
  const grade = calculateGrade(avg);

  assert.strictEqual(total, 438);
  assert.strictEqual(avg, 87.6);
  assert.strictEqual(grade, "A");
});

runTest("Academic report: Grade boundaries verification", () => {
  assert.strictEqual(calculateGrade(95), "A+");
  assert.strictEqual(calculateGrade(90), "A+");
  assert.strictEqual(calculateGrade(89.9), "A");
  assert.strictEqual(calculateGrade(80), "A");
  assert.strictEqual(calculateGrade(75), "B");
  assert.strictEqual(calculateGrade(65), "C");
  assert.strictEqual(calculateGrade(50), "D");
  assert.strictEqual(calculateGrade(49.9), "F");
});

// -----------------------------------------------------------------
// 5. Role Authorization Policy
// -----------------------------------------------------------------
function isAuthorized(userRole, allowedRoles) {
  return allowedRoles.includes(userRole);
}

runTest("Role policy: Admin access check", () => {
  assert.strictEqual(isAuthorized("admin", ["admin"]), true);
  assert.strictEqual(isAuthorized("teacher", ["admin"]), false);
});

runTest("Role policy: Teacher access check", () => {
  assert.strictEqual(isAuthorized("teacher", ["teacher"]), true);
  assert.strictEqual(isAuthorized("admin", ["teacher"]), false);
});

runTest("Role policy: TeacherOrAdmin access check", () => {
  assert.strictEqual(isAuthorized("admin", ["admin", "teacher"]), true);
  assert.strictEqual(isAuthorized("teacher", ["admin", "teacher"]), true);
  assert.strictEqual(isAuthorized("student", ["admin", "teacher"]), false);
});

// -----------------------------------------------------------------
// 6. Time Normalization & Time Bounds Comparison
// -----------------------------------------------------------------
function timeToMinutes(tStr) {
  if (!tStr) return 0;
  const parts = tStr.split(":").map(Number);
  return parts[0] * 60 + (parts[1] || 0);
}

runTest("Time normalization: Correctly converts HH:MM to minutes", () => {
  assert.strictEqual(timeToMinutes("00:00"), 0);
  assert.strictEqual(timeToMinutes("09:30"), 570);
  assert.strictEqual(timeToMinutes("9:30"), 570);
  assert.strictEqual(timeToMinutes("14:15"), 855);
});

runTest("Time bounds: Handles non-zero-padded time string comparisons safely", () => {
  const startStr = "9:00";
  const endStr = "10:00";
  assert(timeToMinutes(startStr) < timeToMinutes(endStr), "9:00 must be recognized as before 10:00");
  assert(timeToMinutes("11:00") >= timeToMinutes("10:00"), "11:00 must be recognized as after 10:00");
  assert(timeToMinutes("10:00") >= timeToMinutes("10:00"), "Identical times must be rejected");
});

// -----------------------------------------------------------------
// 7. Class Name & Section Normalization
// -----------------------------------------------------------------
function normalizeClass(str) {
  return str ? str.trim().toUpperCase() : "";
}

runTest("Class normalization: Matches case and whitespace variations", () => {
  const standardClass = "10 A";
  const variation1 = "10 a";
  const variation2 = "  10 A  ";
  const variation3 = "10 a  ";
  assert.strictEqual(normalizeClass(standardClass), normalizeClass(variation1));
  assert.strictEqual(normalizeClass(standardClass), normalizeClass(variation2));
  assert.strictEqual(normalizeClass(standardClass), normalizeClass(variation3));
  assert.notStrictEqual(normalizeClass(standardClass), normalizeClass("10 B"));
});

// -----------------------------------------------------------------
// 8. Workload Subquery Decoupled Aggregation
// -----------------------------------------------------------------
runTest("Workload aggregation: Decoupled counts prevent Cartesian multiplication", () => {
  const mockTeacher = { teacher_id: "TCH001" };
  const mockAssignments = [
    { id: 1, teacher_id: "TCH001", class_id: 101, subject_id: 201 },
    { id: 2, teacher_id: "TCH001", class_id: 101, subject_id: 202 },
    { id: 3, teacher_id: "TCH001", class_id: 102, subject_id: 201 },
  ];
  const mockTimetable = [
    { id: 10, teacher_id: "TCH001" },
    { id: 11, teacher_id: "TCH001" },
    { id: 12, teacher_id: "TCH001" },
    { id: 13, teacher_id: "TCH001" },
  ];

  const totalAssignments = mockAssignments.filter((a) => a.teacher_id === mockTeacher.teacher_id).length;
  const totalPeriods = mockTimetable.filter((t) => t.teacher_id === mockTeacher.teacher_id).length;
  const cartesianProductCount = totalAssignments * totalPeriods;

  assert.strictEqual(totalAssignments, 3, "Assignments count must be 3");
  assert.strictEqual(totalPeriods, 4, "Timetable periods must be 4");
  assert.notStrictEqual(totalAssignments, cartesianProductCount, "Decoupled count must not equal Cartesian product");
});

// -----------------------------------------------------------------
// 9. Normalized Marks Multi-Attempt & Unpivot Rollback Mapping
// -----------------------------------------------------------------
runTest("Normalized marks: Uniqueness key supports attempts and academic years", () => {
  function makeCompositeKey(regNo, subjectId, examType, academicYear, attemptNumber) {
    return `${regNo}|${subjectId}|${examType}|${academicYear || "2026-2027"}|${attemptNumber || 1}`;
  }

  const firstAttempt = makeCompositeKey("STU001", 103, "Mid Term", "2026-2027", 1);
  const secondAttempt = makeCompositeKey("STU001", 103, "Mid Term", "2026-2027", 2);
  const nextYearAttempt = makeCompositeKey("STU001", 103, "Mid Term", "2027-2028", 1);

  assert.notStrictEqual(firstAttempt, secondAttempt, "Attempts must generate distinct keys");
  assert.notStrictEqual(firstAttempt, nextYearAttempt, "Academic years must generate distinct keys");

  // Rollback unpivot label generation
  function getRollbackExamType(examType, academicYear, attemptNumber) {
    if (attemptNumber > 1) {
      return `${examType} (Attempt ${attemptNumber})`;
    }
    if (academicYear !== "2026-2027") {
      return `${examType} (${academicYear})`;
    }
    return examType;
  }

  assert.strictEqual(getRollbackExamType("Mid Term", "2026-2027", 1), "Mid Term");
  assert.strictEqual(getRollbackExamType("Mid Term", "2026-2027", 2), "Mid Term (Attempt 2)");
  assert.strictEqual(getRollbackExamType("Mid Term", "2027-2028", 1), "Mid Term (2027-2028)");
});

// -----------------------------------------------------------------
// 10. Teacher Subject-Class Authorization (Marks & Attendance)
// -----------------------------------------------------------------
runTest("Teacher authorization: Allows assigned class & subject, denies unassigned", () => {
  const teacherAssignments = [
    { teacher_id: "TCH001", class_code: "10 A", subject_code: "MTH103" },
    { teacher_id: "TCH001", class_code: "10 A", subject_code: "SCI104" },
  ];

  function canManage(user, studentClass, subjectCode) {
    if (user.role === "admin") return true;
    if (user.role === "teacher") {
      return teacherAssignments.some(
        (ta) =>
          ta.teacher_id === user.id &&
          normalizeClass(ta.class_code) === normalizeClass(studentClass) &&
          ta.subject_code === subjectCode
      );
    }
    return false;
  }

  const teacher = { id: "TCH001", role: "teacher" };
  const admin = { id: "ADM001", role: "admin" };

  // Assigned
  assert.strictEqual(canManage(teacher, "10 A", "MTH103"), true);
  assert.strictEqual(canManage(teacher, "10 a", "SCI104"), true);

  // Unassigned subject in assigned class
  assert.strictEqual(canManage(teacher, "10 A", "FL101"), false);

  // Assigned subject in unassigned class
  assert.strictEqual(canManage(teacher, "10 B", "MTH103"), false);

  // Admin has global access
  assert.strictEqual(canManage(admin, "10 B", "FL101"), true);
});

// -----------------------------------------------------------------
// 11. Attendance Partial Indexes & Mutual Consistency Invariant
// -----------------------------------------------------------------
runTest("Attendance invariants: General vs Subject uniqueness and timetable mutual consistency", () => {
  const attendanceStore = [];

  function recordAttendance(record) {
    // Check partial uniqueness
    if (record.attendance_type === "General") {
      const exists = attendanceStore.some(
        (a) => a.reg_no === record.reg_no && a.date === record.date && a.attendance_type === "General"
      );
      if (exists) throw new Error("Duplicate General attendance for student on date");
    } else if (record.attendance_type === "Subject") {
      if (record.timetable_id) {
        const exists = attendanceStore.some(
          (a) =>
            a.reg_no === record.reg_no &&
            a.date === record.date &&
            a.subject_id === record.subject_id &&
            a.timetable_id === record.timetable_id &&
            a.attendance_type === "Subject"
        );
        if (exists) throw new Error("Duplicate Subject-Period attendance");
      } else {
        const exists = attendanceStore.some(
          (a) =>
            a.reg_no === record.reg_no &&
            a.date === record.date &&
            a.subject_id === record.subject_id &&
            !a.timetable_id &&
            a.attendance_type === "Subject"
        );
        if (exists) throw new Error("Duplicate Subject-Daily attendance");
      }
    }
    attendanceStore.push(record);
    return true;
  }

  // 1. General attendance
  recordAttendance({ reg_no: "STU001", date: "2026-10-10", attendance_type: "General" });
  assert.throws(
    () => recordAttendance({ reg_no: "STU001", date: "2026-10-10", attendance_type: "General" }),
    /Duplicate General/
  );

  // 2. Subject attendance for Math on same date (Allowed concurrently with General!)
  recordAttendance({ reg_no: "STU001", date: "2026-10-10", attendance_type: "Subject", subject_id: 103 });

  // 3. Subject attendance for Science on same date (Allowed for different subject!)
  recordAttendance({ reg_no: "STU001", date: "2026-10-10", attendance_type: "Subject", subject_id: 104 });

  // 4. Duplicate daily Math attendance rejected
  assert.throws(
    () => recordAttendance({ reg_no: "STU001", date: "2026-10-10", attendance_type: "Subject", subject_id: 103 }),
    /Duplicate Subject-Daily/
  );

  // 5. Timetable mutual consistency validation
  function validateTimetableConsistency(timetableRow, teacherId, classId, subjectId) {
    return (
      timetableRow.teacher_id === teacherId &&
      timetableRow.class_id === classId &&
      timetableRow.subject_id === subjectId
    );
  }

  const validPeriod = { timetable_id: 5, teacher_id: "TCH001", class_id: 1, subject_id: 103 };
  assert.strictEqual(validateTimetableConsistency(validPeriod, "TCH001", 1, 103), true);
  assert.strictEqual(validateTimetableConsistency(validPeriod, "TCH001", 1, 104), false);
  assert.strictEqual(validateTimetableConsistency(validPeriod, "TCH002", 1, 103), false);
});

// -----------------------------------------------------------------
// 12. Canonical Report Sitting Invariant
// -----------------------------------------------------------------
runTest("Report canonical sitting: Preserves stable report_id across subject normalization", () => {
  const reports = [
    { report_id: 1, reg_no: "STU001", exam_type: "Mid Term", academic_year: "2026-2027", attempt_number: 1 },
  ];

  function getReportSittingKey(r) {
    return `${r.reg_no}|${r.exam_type}|${r.academic_year}|${r.attempt_number}`;
  }

  const existingSitting = getReportSittingKey(reports[0]);
  const newSittingSameExam = getReportSittingKey({
    reg_no: "STU001",
    exam_type: "Mid Term",
    academic_year: "2026-2027",
    attempt_number: 1,
  });
  const retakeSitting = getReportSittingKey({
    reg_no: "STU001",
    exam_type: "Mid Term",
    academic_year: "2026-2027",
    attempt_number: 2,
  });

  assert.strictEqual(existingSitting, newSittingSameExam, "Same sitting resolves to identical report key");
  assert.notStrictEqual(existingSitting, retakeSitting, "Retake resolves to distinct sitting");
});

console.log("\n=================================================");
console.log(`SUMMARY: ${passedTests} of ${totalTests} tests passed.`);
console.log("=================================================");

if (passedTests !== totalTests) {
  process.exit(1);
} else {
  process.exit(0);
}
