-- ============================================================================
-- SCHOOL MANAGEMENT SYSTEM - DATABASE SCHEMA REFERENCE
-- PostgreSQL Database Schema
-- PostgreSQL 18
--
-- school_management database.
-- It documents the captured schema: tables, sequences, views, indexes,
-- constraints, and foreign keys.
--
-- IMPORTANT:
--   * This is a schema snapshot, not a migration script.
--   * Do NOT run this against an existing school_management database.
--   * To create a fresh database from scratch, use an EMPTY database only,
--     and review/test this file first.
--   * No table data or sequence current values are included here. 
--     Only the schema structure is captured. Application data is not included.
--   * The legacy public.marks table and public.legacy_marks_archive are
--     intentionally retained because they exist in the captured database.
-- ============================================================================

--

-- PostgreSQL database

--



SET statement_timeout = 0;

SET lock_timeout = 0;

SET idle_in_transaction_session_timeout = 0;

SET transaction_timeout = 0;

SET client_encoding = 'UTF8';

SET standard_conforming_strings = on;

SELECT pg_catalog.set_config('search_path', '', false);

SET check_function_bodies = false;

SET xmloption = content;

SET client_min_messages = warning;

SET row_security = off;



SET default_tablespace = '';



SET default_table_access_method = heap;



--

-- Name: administrator; Type: TABLE; Schema: public; Owner: --

--



CREATE TABLE public.administrator (

    admin_id character varying(10) NOT NULL,

    username character varying(50) NOT NULL,

    password character varying(255) NOT NULL,

    role character varying(20) DEFAULT 'admin'::character varying NOT NULL

);





--

-- Name: announcements; Type: TABLE; Schema: public; Owner: --

--



CREATE TABLE public.announcements (

    announcement_id integer NOT NULL,

    title character varying(200) NOT NULL,

    content text NOT NULL,

    target_audience character varying(20) DEFAULT 'All'::character varying NOT NULL,

    is_active boolean DEFAULT true NOT NULL,

    created_by character varying(50) NOT NULL,

    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,

    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,

    CONSTRAINT announcements_target_audience_check CHECK (((target_audience)::text = ANY ((ARRAY['All'::character varying, 'Teachers'::character varying, 'Students'::character varying])::text[])))

);





--

-- Name: announcements_announcement_id_seq; Type: SEQUENCE; Schema: public; Owner: --

--



CREATE SEQUENCE public.announcements_announcement_id_seq

    AS integer

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1;





--

-- Name: announcements_announcement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: --

--



ALTER SEQUENCE public.announcements_announcement_id_seq OWNED BY public.announcements.announcement_id;





--

-- Name: attendance; Type: TABLE; Schema: public; Owner: --

--



CREATE TABLE public.attendance (

    attend_id integer NOT NULL,

    reg_no character varying(15) NOT NULL,

    attendance_date date NOT NULL,

    status character varying(10) NOT NULL,

    subject_id integer,

    timetable_id integer,

    assignment_id integer,

    attendance_type character varying(20) DEFAULT 'Subject'::character varying NOT NULL,

    recorded_by character varying(15),

    CONSTRAINT chk_attendance_status CHECK (((status)::text = ANY ((ARRAY['Present'::character varying, 'Absent'::character varying])::text[])))

);





--

-- Name: attendance_attend_id_seq; Type: SEQUENCE; Schema: public; Owner: --

--



ALTER TABLE public.attendance ALTER COLUMN attend_id ADD GENERATED ALWAYS AS IDENTITY (

    SEQUENCE NAME public.attendance_attend_id_seq

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1

);





--

-- Name: classes; Type: TABLE; Schema: public; Owner: --

--



CREATE TABLE public.classes (

    class_id integer NOT NULL,

    class_name character varying(20) NOT NULL,

    section character varying(10) NOT NULL,

    academic_year character varying(20) DEFAULT '2026-2027'::character varying NOT NULL,

    class_code character varying(30) NOT NULL

);





--

-- Name: classes_class_id_seq; Type: SEQUENCE; Schema: public; Owner: --

--



CREATE SEQUENCE public.classes_class_id_seq

    AS integer

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1;





--

-- Name: classes_class_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: --

--



ALTER SEQUENCE public.classes_class_id_seq OWNED BY public.classes.class_id;





--

-- Name: legacy_marks_archive; Type: TABLE; Schema: public; Owner: --

--



CREATE TABLE public.legacy_marks_archive (

    archive_id integer NOT NULL,

    original_mark_id integer NOT NULL,

    reg_no character varying(15) NOT NULL,

    exam_type character varying(30) NOT NULL,

    subject_code character varying(20) DEFAULT 'OTH106'::character varying NOT NULL,

    subject_name character varying(50) DEFAULT 'Others'::character varying NOT NULL,

    marks_obtained integer,

    status character varying(20) NOT NULL,

    archived_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL

);





--

-- Name: legacy_marks_archive_archive_id_seq; Type: SEQUENCE; Schema: public; Owner: --

--



CREATE SEQUENCE public.legacy_marks_archive_archive_id_seq

    AS integer

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1;





--

-- Name: legacy_marks_archive_archive_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: --

--



ALTER SEQUENCE public.legacy_marks_archive_archive_id_seq OWNED BY public.legacy_marks_archive.archive_id;





--

-- Name: marks; Type: TABLE; Schema: public; Owner: --

--



CREATE TABLE public.marks (

    mark_id integer NOT NULL,

    reg_no character varying(15) NOT NULL,

    exam_type character varying(30) NOT NULL,

    first_language integer NOT NULL,

    second_language integer NOT NULL,

    mathematics integer NOT NULL,

    science integer NOT NULL,

    arts integer NOT NULL,

    others integer NOT NULL,

    CONSTRAINT chk_arts CHECK (((arts >= 0) AND (arts <= 100))),

    CONSTRAINT chk_first_language CHECK (((first_language >= 0) AND (first_language <= 100))),

    CONSTRAINT chk_mathematics CHECK (((mathematics >= 0) AND (mathematics <= 100))),

    CONSTRAINT chk_others CHECK (((others >= 0) AND (others <= 100))),

    CONSTRAINT chk_science CHECK (((science >= 0) AND (science <= 100))),

    CONSTRAINT chk_second_language CHECK (((second_language >= 0) AND (second_language <= 100)))

);





--

-- Name: marks_mark_id_seq; Type: SEQUENCE; Schema: public; Owner: --

--



ALTER TABLE public.marks ALTER COLUMN mark_id ADD GENERATED ALWAYS AS IDENTITY (

    SEQUENCE NAME public.marks_mark_id_seq

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1

);





--

-- Name: report; Type: TABLE; Schema: public; Owner: --

--



CREATE TABLE public.report (

    report_id integer NOT NULL,

    mark_id integer,

    reg_no character varying(15) NOT NULL,

    exam_type character varying(50),

    academic_year character varying(20) DEFAULT '2026-2027'::character varying NOT NULL,

    attempt_number integer DEFAULT 1 NOT NULL

);





--

-- Name: report_report_id_seq; Type: SEQUENCE; Schema: public; Owner: --

--



ALTER TABLE public.report ALTER COLUMN report_id ADD GENERATED ALWAYS AS IDENTITY (

    SEQUENCE NAME public.report_report_id_seq

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1

);





--

-- Name: student; Type: TABLE; Schema: public; Owner: -

--



CREATE TABLE public.student (

    reg_no character varying(15) NOT NULL,

    full_name character varying(100) NOT NULL,

    class character varying(20) NOT NULL,

    date_of_birth date NOT NULL,

    gender character varying(10) NOT NULL,

    phone character varying(15) NOT NULL,

    email character varying(100) NOT NULL,

    admin_id character varying(10) NOT NULL,

    house_no character varying(20),

    city character varying(50),

    pin character varying(10),

    CONSTRAINT chk_student_gender CHECK (((gender)::text = ANY ((ARRAY['Male'::character varying, 'Female'::character varying, 'Other'::character varying])::text[])))

);





--

-- Name: student_details; Type: VIEW; Schema: public; Owner: -

--



CREATE VIEW public.student_details AS

 SELECT reg_no,

    full_name,

    class,

    date_of_birth,

    (EXTRACT(year FROM age((CURRENT_DATE)::timestamp with time zone, (date_of_birth)::timestamp with time zone)))::integer AS age,

    gender,

    phone,

    email,

    admin_id,

    house_no,

    city,

    pin

   FROM public.student;





--

-- Name: student_subject_marks; Type: TABLE; Schema: public; Owner: -

--



CREATE TABLE public.student_subject_marks (

    mark_record_id integer NOT NULL,

    reg_no character varying(15) NOT NULL,

    subject_id integer NOT NULL,

    exam_type character varying(30) NOT NULL,

    academic_year character varying(20) DEFAULT '2026-2027'::character varying NOT NULL,

    attempt_number integer DEFAULT 1 NOT NULL,

    marks_obtained integer NOT NULL,

    recorded_by character varying(15),

    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,

    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT student_subject_marks_marks_obtained_check CHECK (((marks_obtained >= 0) AND (marks_obtained <= 100)))

);





--

-- Name: subjects; Type: TABLE; Schema: public; Owner: -

--



CREATE TABLE public.subjects (

    subject_id integer NOT NULL,

    subject_code character varying(20) NOT NULL,

    subject_name character varying(100) NOT NULL,

    department character varying(50)

);





--

-- Name: student_reports; Type: VIEW; Schema: public; Owner: -

--



CREATE VIEW public.student_reports AS

 SELECT r.report_id,

    r.reg_no,

    s.full_name,

    s.class,

    r.exam_type,

    r.academic_year,

    r.attempt_number,

    max(

        CASE

            WHEN ((sub.subject_code)::text = 'FL101'::text) THEN m.marks_obtained

            ELSE NULL::integer

        END) AS first_language,

    max(

        CASE

            WHEN ((sub.subject_code)::text = 'SL102'::text) THEN m.marks_obtained

            ELSE NULL::integer

        END) AS second_language,

    max(

        CASE

            WHEN ((sub.subject_code)::text = 'MTH103'::text) THEN m.marks_obtained

            ELSE NULL::integer

        END) AS mathematics,

    max(

        CASE

            WHEN ((sub.subject_code)::text = 'SCI104'::text) THEN m.marks_obtained

            ELSE NULL::integer

        END) AS science,

    max(

        CASE

            WHEN ((sub.subject_code)::text = 'ART105'::text) THEN m.marks_obtained

            ELSE NULL::integer

        END) AS arts,

    COALESCE(sum(m.marks_obtained), (0)::bigint) AS total_marks,

    COALESCE(round(((sum(m.marks_obtained))::numeric / 5.0), 2), (0)::numeric) AS average,

        CASE

            WHEN (((sum(m.marks_obtained))::numeric / 5.0) >= (90)::numeric) THEN 'A+'::text

            WHEN (((sum(m.marks_obtained))::numeric / 5.0) >= (80)::numeric) THEN 'A'::text

            WHEN (((sum(m.marks_obtained))::numeric / 5.0) >= (70)::numeric) THEN 'B'::text

            WHEN (((sum(m.marks_obtained))::numeric / 5.0) >= (60)::numeric) THEN 'C'::text

            WHEN (((sum(m.marks_obtained))::numeric / 5.0) >= (50)::numeric) THEN 'D'::text

            ELSE 'F'::text

        END AS grade

   FROM (((public.report r

     JOIN public.student s ON (((r.reg_no)::text = (s.reg_no)::text)))

     LEFT JOIN public.student_subject_marks m ON ((((r.reg_no)::text = (m.reg_no)::text) AND ((r.exam_type)::text = (m.exam_type)::text) AND ((r.academic_year)::text = (m.academic_year)::text) AND (r.attempt_number = m.attempt_number))))

     LEFT JOIN public.subjects sub ON ((m.subject_id = sub.subject_id)))

  GROUP BY r.report_id, r.reg_no, s.full_name, s.class, r.exam_type, r.academic_year, r.attempt_number;





--

-- Name: student_subject_marks_mark_record_id_seq; Type: SEQUENCE; Schema: public; Owner: -

--



CREATE SEQUENCE public.student_subject_marks_mark_record_id_seq

    AS integer

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1;





--

-- Name: student_subject_marks_mark_record_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

--



ALTER SEQUENCE public.student_subject_marks_mark_record_id_seq OWNED BY public.student_subject_marks.mark_record_id;





--

-- Name: subjects_subject_id_seq; Type: SEQUENCE; Schema: public; Owner: -

--



CREATE SEQUENCE public.subjects_subject_id_seq

    AS integer

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1;





--

-- Name: subjects_subject_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

--



ALTER SEQUENCE public.subjects_subject_id_seq OWNED BY public.subjects.subject_id;





--

-- Name: teacher; Type: TABLE; Schema: public; Owner: -

--



CREATE TABLE public.teacher (

    teacher_id character varying(15) NOT NULL,

    full_name character varying(100) NOT NULL,

    email character varying(100) NOT NULL,

    phone character varying(15) NOT NULL,

    qualification character varying(100),

    specialization character varying(100),

    joining_date date DEFAULT CURRENT_DATE NOT NULL,

    status character varying(20) DEFAULT 'Active'::character varying NOT NULL,

    password_hash character varying(255) NOT NULL,

    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT teacher_status_check CHECK (((status)::text = ANY ((ARRAY['Active'::character varying, 'Inactive'::character varying, 'Suspended'::character varying])::text[])))

);





--

-- Name: teacher_assignment; Type: TABLE; Schema: public; Owner: -

--



CREATE TABLE public.teacher_assignment (

    assignment_id integer NOT NULL,

    teacher_id character varying(15) NOT NULL,

    class_id integer NOT NULL,

    subject_id integer NOT NULL,

    academic_year character varying(20) DEFAULT '2026-2027'::character varying NOT NULL,

    assigned_date date DEFAULT CURRENT_DATE NOT NULL

);





--

-- Name: teacher_assignment_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: -

--



CREATE SEQUENCE public.teacher_assignment_assignment_id_seq

    AS integer

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1;





--

-- Name: teacher_assignment_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

--



ALTER SEQUENCE public.teacher_assignment_assignment_id_seq OWNED BY public.teacher_assignment.assignment_id;





--

-- Name: timetable; Type: TABLE; Schema: public; Owner: -

--



CREATE TABLE public.timetable (

    timetable_id integer NOT NULL,

    class_id integer NOT NULL,

    subject_id integer NOT NULL,

    teacher_id character varying(15) NOT NULL,

    day_of_week character varying(15) NOT NULL,

    start_time time without time zone NOT NULL,

    end_time time without time zone NOT NULL,

    room_number character varying(20),

    CONSTRAINT chk_timetable_time CHECK ((end_time > start_time)),

    CONSTRAINT timetable_day_of_week_check CHECK (((day_of_week)::text = ANY ((ARRAY['Monday'::character varying, 'Tuesday'::character varying, 'Wednesday'::character varying, 'Thursday'::character varying, 'Friday'::character varying, 'Saturday'::character varying])::text[])))

);





--

-- Name: timetable_timetable_id_seq; Type: SEQUENCE; Schema: public; Owner: -

--



CREATE SEQUENCE public.timetable_timetable_id_seq

    AS integer

    START WITH 1

    INCREMENT BY 1

    NO MINVALUE

    NO MAXVALUE

    CACHE 1;





--

-- Name: timetable_timetable_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

--



ALTER SEQUENCE public.timetable_timetable_id_seq OWNED BY public.timetable.timetable_id;





--

-- Name: announcements announcement_id; Type: DEFAULT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.announcements ALTER COLUMN announcement_id SET DEFAULT nextval('public.announcements_announcement_id_seq'::regclass);





--

-- Name: classes class_id; Type: DEFAULT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.classes ALTER COLUMN class_id SET DEFAULT nextval('public.classes_class_id_seq'::regclass);





--

-- Name: legacy_marks_archive archive_id; Type: DEFAULT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.legacy_marks_archive ALTER COLUMN archive_id SET DEFAULT nextval('public.legacy_marks_archive_archive_id_seq'::regclass);





--

-- Name: student_subject_marks mark_record_id; Type: DEFAULT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student_subject_marks ALTER COLUMN mark_record_id SET DEFAULT nextval('public.student_subject_marks_mark_record_id_seq'::regclass);





--

-- Name: subjects subject_id; Type: DEFAULT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.subjects ALTER COLUMN subject_id SET DEFAULT nextval('public.subjects_subject_id_seq'::regclass);





--

-- Name: teacher_assignment assignment_id; Type: DEFAULT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.teacher_assignment ALTER COLUMN assignment_id SET DEFAULT nextval('public.teacher_assignment_assignment_id_seq'::regclass);





--

-- Name: timetable timetable_id; Type: DEFAULT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.timetable ALTER COLUMN timetable_id SET DEFAULT nextval('public.timetable_timetable_id_seq'::regclass);





--

-- Name: administrator administrator_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.administrator

    ADD CONSTRAINT administrator_pkey PRIMARY KEY (admin_id);





--

-- Name: administrator administrator_username_key; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.administrator

    ADD CONSTRAINT administrator_username_key UNIQUE (username);





--

-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.announcements

    ADD CONSTRAINT announcements_pkey PRIMARY KEY (announcement_id);





--

-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.attendance

    ADD CONSTRAINT attendance_pkey PRIMARY KEY (attend_id);





--

-- Name: classes classes_class_code_key; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.classes

    ADD CONSTRAINT classes_class_code_key UNIQUE (class_code);





--

-- Name: classes classes_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.classes

    ADD CONSTRAINT classes_pkey PRIMARY KEY (class_id);





--

-- Name: legacy_marks_archive legacy_marks_archive_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.legacy_marks_archive

    ADD CONSTRAINT legacy_marks_archive_pkey PRIMARY KEY (archive_id);





--

-- Name: marks marks_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.marks

    ADD CONSTRAINT marks_pkey PRIMARY KEY (mark_id);





--

-- Name: report report_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.report

    ADD CONSTRAINT report_pkey PRIMARY KEY (report_id);





--

-- Name: student student_email_key; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student

    ADD CONSTRAINT student_email_key UNIQUE (email);





--

-- Name: student student_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student

    ADD CONSTRAINT student_pkey PRIMARY KEY (reg_no);





--

-- Name: student_subject_marks student_subject_marks_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student_subject_marks

    ADD CONSTRAINT student_subject_marks_pkey PRIMARY KEY (mark_record_id);





--

-- Name: subjects subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.subjects

    ADD CONSTRAINT subjects_pkey PRIMARY KEY (subject_id);





--

-- Name: subjects subjects_subject_code_key; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.subjects

    ADD CONSTRAINT subjects_subject_code_key UNIQUE (subject_code);





--

-- Name: teacher_assignment teacher_assignment_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.teacher_assignment

    ADD CONSTRAINT teacher_assignment_pkey PRIMARY KEY (assignment_id);





--

-- Name: teacher teacher_email_key; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.teacher

    ADD CONSTRAINT teacher_email_key UNIQUE (email);





--

-- Name: teacher teacher_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.teacher

    ADD CONSTRAINT teacher_pkey PRIMARY KEY (teacher_id);





--

-- Name: timetable timetable_pkey; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.timetable

    ADD CONSTRAINT timetable_pkey PRIMARY KEY (timetable_id);





--

-- Name: classes uq_class_section_year; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.classes

    ADD CONSTRAINT uq_class_section_year UNIQUE (class_name, section, academic_year);





--

-- Name: report uq_report_sitting; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.report

    ADD CONSTRAINT uq_report_sitting UNIQUE (reg_no, exam_type, academic_year, attempt_number);





--

-- Name: student_subject_marks uq_student_subject_exam_attempt; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student_subject_marks

    ADD CONSTRAINT uq_student_subject_exam_attempt UNIQUE (reg_no, subject_id, exam_type, academic_year, attempt_number);





--

-- Name: teacher_assignment uq_teacher_class_subject; Type: CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.teacher_assignment

    ADD CONSTRAINT uq_teacher_class_subject UNIQUE (teacher_id, class_id, subject_id, academic_year);





--

-- Name: idx_announcements_active; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_announcements_active ON public.announcements USING btree (is_active, target_audience);





--

-- Name: idx_attendance_reg_no; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_attendance_reg_no ON public.attendance USING btree (reg_no);





--

-- Name: idx_attendance_student_date; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_attendance_student_date ON public.attendance USING btree (reg_no, attendance_date);





--

-- Name: idx_attendance_subject_date; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_attendance_subject_date ON public.attendance USING btree (subject_id, attendance_date);





--

-- Name: idx_marks_reg_no; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_marks_reg_no ON public.marks USING btree (reg_no);





--

-- Name: idx_student_class; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_student_class ON public.student USING btree (class);





--

-- Name: idx_sub_marks_exam; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_sub_marks_exam ON public.student_subject_marks USING btree (exam_type, academic_year);





--

-- Name: idx_sub_marks_student; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_sub_marks_student ON public.student_subject_marks USING btree (reg_no);





--

-- Name: idx_sub_marks_subject; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_sub_marks_subject ON public.student_subject_marks USING btree (subject_id);





--

-- Name: idx_teacher_assignment_class; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_teacher_assignment_class ON public.teacher_assignment USING btree (class_id);





--

-- Name: idx_teacher_assignment_teacher; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_teacher_assignment_teacher ON public.teacher_assignment USING btree (teacher_id);





--

-- Name: idx_teacher_email; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_teacher_email ON public.teacher USING btree (email);





--

-- Name: idx_teacher_status; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_teacher_status ON public.teacher USING btree (status);





--

-- Name: idx_timetable_class; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_timetable_class ON public.timetable USING btree (class_id, day_of_week);





--

-- Name: idx_timetable_teacher; Type: INDEX; Schema: public; Owner: -

--



CREATE INDEX idx_timetable_teacher ON public.timetable USING btree (teacher_id, day_of_week);





--

-- Name: uq_attendance_general; Type: INDEX; Schema: public; Owner: -

--



CREATE UNIQUE INDEX uq_attendance_general ON public.attendance USING btree (reg_no, attendance_date) WHERE ((attendance_type)::text = 'General'::text);





--

-- Name: uq_attendance_subject_daily; Type: INDEX; Schema: public; Owner: -

--



CREATE UNIQUE INDEX uq_attendance_subject_daily ON public.attendance USING btree (reg_no, attendance_date, subject_id) WHERE (((attendance_type)::text = 'Subject'::text) AND (timetable_id IS NULL) AND (subject_id IS NOT NULL));





--

-- Name: uq_attendance_subject_period; Type: INDEX; Schema: public; Owner: -

--



CREATE UNIQUE INDEX uq_attendance_subject_period ON public.attendance USING btree (reg_no, attendance_date, subject_id, timetable_id) WHERE (((attendance_type)::text = 'Subject'::text) AND (timetable_id IS NOT NULL));





--

-- Name: attendance attendance_assignment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.attendance

    ADD CONSTRAINT attendance_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.teacher_assignment(assignment_id) ON DELETE SET NULL;





--

-- Name: attendance attendance_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.attendance

    ADD CONSTRAINT attendance_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.teacher(teacher_id) ON DELETE SET NULL;





--

-- Name: attendance attendance_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.attendance

    ADD CONSTRAINT attendance_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(subject_id) ON DELETE CASCADE;





--

-- Name: attendance attendance_timetable_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.attendance

    ADD CONSTRAINT attendance_timetable_id_fkey FOREIGN KEY (timetable_id) REFERENCES public.timetable(timetable_id) ON DELETE SET NULL;





--

-- Name: attendance fk_attendance_student; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.attendance

    ADD CONSTRAINT fk_attendance_student FOREIGN KEY (reg_no) REFERENCES public.student(reg_no);





--

-- Name: marks fk_marks_student; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.marks

    ADD CONSTRAINT fk_marks_student FOREIGN KEY (reg_no) REFERENCES public.student(reg_no);





--

-- Name: report fk_report_student; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.report

    ADD CONSTRAINT fk_report_student FOREIGN KEY (reg_no) REFERENCES public.student(reg_no);





--

-- Name: student fk_student_admin; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student

    ADD CONSTRAINT fk_student_admin FOREIGN KEY (admin_id) REFERENCES public.administrator(admin_id);





--

-- Name: student_subject_marks student_subject_marks_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student_subject_marks

    ADD CONSTRAINT student_subject_marks_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.teacher(teacher_id) ON DELETE SET NULL;





--

-- Name: student_subject_marks student_subject_marks_reg_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student_subject_marks

    ADD CONSTRAINT student_subject_marks_reg_no_fkey FOREIGN KEY (reg_no) REFERENCES public.student(reg_no) ON DELETE CASCADE;





--

-- Name: student_subject_marks student_subject_marks_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.student_subject_marks

    ADD CONSTRAINT student_subject_marks_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(subject_id) ON DELETE CASCADE;





--

-- Name: teacher_assignment teacher_assignment_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.teacher_assignment

    ADD CONSTRAINT teacher_assignment_class_id_fkey FOREIGN KEY (class_id) REFERENCES public.classes(class_id) ON DELETE CASCADE;





--

-- Name: teacher_assignment teacher_assignment_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.teacher_assignment

    ADD CONSTRAINT teacher_assignment_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(subject_id) ON DELETE CASCADE;





--

-- Name: teacher_assignment teacher_assignment_teacher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.teacher_assignment

    ADD CONSTRAINT teacher_assignment_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES public.teacher(teacher_id) ON DELETE CASCADE;





--

-- Name: timetable timetable_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.timetable

    ADD CONSTRAINT timetable_class_id_fkey FOREIGN KEY (class_id) REFERENCES public.classes(class_id) ON DELETE CASCADE;





--

-- Name: timetable timetable_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.timetable

    ADD CONSTRAINT timetable_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.subjects(subject_id) ON DELETE CASCADE;





--

-- Name: timetable timetable_teacher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

--



ALTER TABLE ONLY public.timetable

    ADD CONSTRAINT timetable_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES public.teacher(teacher_id) ON DELETE CASCADE;





--

-- PostgreSQL database dump complete

--
